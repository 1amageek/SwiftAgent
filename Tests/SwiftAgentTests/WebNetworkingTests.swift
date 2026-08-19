import Foundation
import Testing
@testable import AgentTools

@Suite("AgentTools web boundaries")
struct WebNetworkingTests {
    @Test("Trusted origins require encrypted or loopback transport")
    func trustedOriginsRejectRemotePlaintextHTTP() throws {
        #expect(throws: WebHTTPError.self) {
            _ = try WebOrigin(scheme: "http", host: "public.example")
        }
        _ = try WebOrigin(scheme: "http", host: "127.0.0.1")
    }

    @Test("Unauthorized origins are rejected before the HTTP client", .timeLimit(.minutes(1)))
    func unauthorizedOriginDoesNotReachClient() async throws {
        let client = RecordingWebHTTPClient(responses: [])
        let fetcher = PolicyEnforcedWebDocumentFetcher(
            client: client,
            policy: TrustedOriginsWebURLPolicy(origins: [
                try WebOrigin(scheme: "https", host: "allowed.example")
            ])
        )

        await #expect(throws: WebHTTPError.self) {
            _ = try await fetcher.fetch(WebDocumentRequest(
                url: try #require(URL(string: "https://denied.example/document"))
            ))
        }
        #expect(await client.requestCount() == 0)
    }

    @Test("URL authorization consumes the end-to-end deadline", .timeLimit(.minutes(1)))
    func authorizationConsumesDeadline() async throws {
        let url = try #require(URL(string: "https://allowed.example/data"))
        let fetcher = PolicyEnforcedWebDocumentFetcher(
            client: RecordingWebHTTPClient(responses: []),
            policy: SuspendingWebURLPolicy()
        )

        await #expect(throws: WebHTTPError.self) {
            _ = try await fetcher.fetch(WebDocumentRequest(
                url: url,
                timeout: .milliseconds(10)
            ))
        }
    }

    @Test("HTTP clients cannot exceed the end-to-end deadline", .timeLimit(.minutes(1)))
    func clientConsumesDeadline() async throws {
        let url = try #require(URL(string: "https://allowed.example/data"))
        let fetcher = PolicyEnforcedWebDocumentFetcher(
            client: SuspendingWebHTTPClient(),
            policy: TrustedOriginsWebURLPolicy(origins: [
                try WebOrigin(scheme: "https", host: "allowed.example")
            ])
        )

        await #expect(throws: WebHTTPError.self) {
            _ = try await fetcher.fetch(WebDocumentRequest(
                url: url,
                timeout: .milliseconds(10)
            ))
        }
    }

    @Test("Every redirect destination is independently authorized", .timeLimit(.minutes(1)))
    func redirectDestinationIsReauthorized() async throws {
        let originURL = try #require(URL(string: "https://allowed.example/start"))
        let client = RecordingWebHTTPClient(responses: [
            WebHTTPResponse(
                url: originURL,
                statusCode: 302,
                headers: ["location": "https://denied.example/target"],
                body: Data()
            )
        ])
        let fetcher = PolicyEnforcedWebDocumentFetcher(
            client: client,
            policy: TrustedOriginsWebURLPolicy(origins: [
                try WebOrigin(scheme: "https", host: "allowed.example")
            ])
        )

        await #expect(throws: WebHTTPError.self) {
            _ = try await fetcher.fetch(WebDocumentRequest(url: originURL))
        }
        #expect(await client.requestCount() == 1)
    }

    @Test("Fetcher defends its size contract against a nonconforming client", .timeLimit(.minutes(1)))
    func fetcherRechecksBodySize() async throws {
        let url = try #require(URL(string: "https://allowed.example/data"))
        let client = RecordingWebHTTPClient(responses: [
            WebHTTPResponse(
                url: url,
                statusCode: 200,
                headers: [:],
                body: Data(repeating: 0, count: 5)
            )
        ])
        let fetcher = PolicyEnforcedWebDocumentFetcher(
            client: client,
            policy: TrustedOriginsWebURLPolicy(origins: [
                try WebOrigin(scheme: "https", host: "allowed.example")
            ])
        )

        await #expect(throws: WebHTTPError.self) {
            _ = try await fetcher.fetch(WebDocumentRequest(
                url: url,
                maximumBodyBytes: 4
            ))
        }
    }

    @Test("A client cannot smuggle an unapproved response URL", .timeLimit(.minutes(1)))
    func responseURLMustMatchRequestURL() async throws {
        let requestedURL = try #require(URL(string: "https://allowed.example/data"))
        let client = RecordingWebHTTPClient(responses: [
            WebHTTPResponse(
                url: try #require(URL(string: "https://denied.example/data")),
                statusCode: 200,
                headers: [:],
                body: Data()
            )
        ])
        let fetcher = PolicyEnforcedWebDocumentFetcher(
            client: client,
            policy: TrustedOriginsWebURLPolicy(origins: [
                try WebOrigin(scheme: "https", host: "allowed.example")
            ])
        )

        await #expect(throws: WebHTTPError.self) {
            _ = try await fetcher.fetch(WebDocumentRequest(url: requestedURL))
        }
    }

    @Test("Routing headers are rejected before the HTTP client", .timeLimit(.minutes(1)))
    func routingHeadersAreRejected() async throws {
        let url = try #require(URL(string: "https://allowed.example/data"))
        let client = RecordingWebHTTPClient(responses: [])
        let fetcher = PolicyEnforcedWebDocumentFetcher(
            client: client,
            policy: TrustedOriginsWebURLPolicy(origins: [
                try WebOrigin(scheme: "https", host: "allowed.example")
            ])
        )

        await #expect(throws: WebHTTPError.self) {
            _ = try await fetcher.fetch(WebDocumentRequest(
                url: url,
                headers: ["Host": "different.example"]
            ))
        }
        #expect(await client.requestCount() == 0)
    }

    @Test("Cross-origin redirects discard caller headers", .timeLimit(.minutes(1)))
    func crossOriginRedirectDiscardsHeaders() async throws {
        let firstURL = try #require(URL(string: "https://first.example/start"))
        let secondURL = try #require(URL(string: "https://second.example/end"))
        let client = RecordingWebHTTPClient(responses: [
            WebHTTPResponse(
                url: firstURL,
                statusCode: 302,
                headers: ["location": secondURL.absoluteString],
                body: Data()
            ),
            WebHTTPResponse(
                url: secondURL,
                statusCode: 200,
                headers: [:],
                body: Data("ok".utf8)
            ),
        ])
        let fetcher = PolicyEnforcedWebDocumentFetcher(
            client: client,
            policy: TrustedOriginsWebURLPolicy(origins: [
                try WebOrigin(scheme: "https", host: "first.example"),
                try WebOrigin(scheme: "https", host: "second.example"),
            ])
        )

        _ = try await fetcher.fetch(WebDocumentRequest(
            url: firstURL,
            headers: ["X-API-Key": "secret", "Accept": "text/plain"]
        ))

        let requests = await client.recordedRequests()
        #expect(requests.count == 2)
        #expect(requests.first?.headers["X-API-Key"] == "secret")
        #expect(requests.last?.headers.isEmpty == true)
    }

    @Test("Cache hits still enforce the caller body limit", .timeLimit(.minutes(1)))
    func cachedBodyLimitIsRechecked() async throws {
        let url = try #require(URL(string: "https://allowed.example/data"))
        let client = RecordingWebHTTPClient(responses: [
            WebHTTPResponse(
                url: url,
                statusCode: 200,
                headers: [:],
                body: Data(repeating: 0, count: 5)
            )
        ])
        let fetcher = PolicyEnforcedWebDocumentFetcher(
            client: client,
            policy: TrustedOriginsWebURLPolicy(origins: [
                try WebOrigin(scheme: "https", host: "allowed.example")
            ])
        )

        _ = try await fetcher.fetch(WebDocumentRequest(
            url: url,
            maximumBodyBytes: 5
        ))
        await #expect(throws: WebHTTPError.self) {
            _ = try await fetcher.fetch(WebDocumentRequest(
                url: url,
                maximumBodyBytes: 4
            ))
        }
        #expect(await client.requestCount() == 1)
    }

    @Test("Cache-Control max-age zero is never cached", .timeLimit(.minutes(1)))
    func zeroMaxAgeIsNotCached() async throws {
        let url = try #require(URL(string: "https://allowed.example/data"))
        let response = WebHTTPResponse(
            url: url,
            statusCode: 200,
            headers: ["cache-control": "public, max-age=0"],
            body: Data("fresh".utf8)
        )
        let client = RecordingWebHTTPClient(responses: [response, response])
        let fetcher = PolicyEnforcedWebDocumentFetcher(
            client: client,
            policy: TrustedOriginsWebURLPolicy(origins: [
                try WebOrigin(scheme: "https", host: "allowed.example")
            ])
        )

        _ = try await fetcher.fetch(WebDocumentRequest(url: url))
        _ = try await fetcher.fetch(WebDocumentRequest(url: url))

        #expect(await client.requestCount() == 2)
    }

    @Test("Conflicting max-age directives use the shortest freshness", .timeLimit(.minutes(1)))
    func conflictingMaxAgeIsNotCached() async throws {
        let url = try #require(URL(string: "https://allowed.example/data"))
        let response = WebHTTPResponse(
            url: url,
            statusCode: 200,
            headers: ["cache-control": "public, max-age=60, max-age=0"],
            body: Data("fresh".utf8)
        )
        let client = RecordingWebHTTPClient(responses: [response, response])
        let fetcher = PolicyEnforcedWebDocumentFetcher(
            client: client,
            policy: TrustedOriginsWebURLPolicy(origins: [
                try WebOrigin(scheme: "https", host: "allowed.example")
            ])
        )

        _ = try await fetcher.fetch(WebDocumentRequest(url: url))
        _ = try await fetcher.fetch(WebDocumentRequest(url: url))

        #expect(await client.requestCount() == 2)
    }

    @Test("Pragma no-cache is found among multiple directives", .timeLimit(.minutes(1)))
    func compoundPragmaNoCacheIsNotCached() async throws {
        let url = try #require(URL(string: "https://allowed.example/data"))
        let response = WebHTTPResponse(
            url: url,
            statusCode: 200,
            headers: ["pragma": "extension, no-cache"],
            body: Data("fresh".utf8)
        )
        let client = RecordingWebHTTPClient(responses: [response, response])
        let fetcher = PolicyEnforcedWebDocumentFetcher(
            client: client,
            policy: TrustedOriginsWebURLPolicy(origins: [
                try WebOrigin(scheme: "https", host: "allowed.example")
            ])
        )

        _ = try await fetcher.fetch(WebDocumentRequest(url: url))
        _ = try await fetcher.fetch(WebDocumentRequest(url: url))

        #expect(await client.requestCount() == 2)
    }

    @Test("Cached redirect destinations are reauthorized", .timeLimit(.minutes(1)))
    func cachedRedirectDestinationIsReauthorized() async throws {
        let firstURL = try #require(URL(string: "https://first.example/start"))
        let secondURL = try #require(URL(string: "https://second.example/end"))
        let policy = MutableWebURLPolicy(origins: [
            try WebOrigin(scheme: "https", host: "first.example"),
            try WebOrigin(scheme: "https", host: "second.example"),
        ])
        let client = RecordingWebHTTPClient(responses: [
            WebHTTPResponse(
                url: firstURL,
                statusCode: 302,
                headers: ["location": secondURL.absoluteString],
                body: Data()
            ),
            WebHTTPResponse(
                url: secondURL,
                statusCode: 200,
                headers: [:],
                body: Data("cached".utf8)
            ),
        ])
        let fetcher = PolicyEnforcedWebDocumentFetcher(
            client: client,
            policy: policy
        )

        _ = try await fetcher.fetch(WebDocumentRequest(url: firstURL))
        await policy.remove(
            try WebOrigin(scheme: "https", host: "second.example")
        )

        await #expect(throws: WebHTTPError.self) {
            _ = try await fetcher.fetch(WebDocumentRequest(url: firstURL))
        }
        #expect(await client.requestCount() == 2)
    }

    @Test("Responses with Vary are not cached", .timeLimit(.minutes(1)))
    func varyingResponseIsNotCached() async throws {
        let url = try #require(URL(string: "https://allowed.example/data"))
        let response = WebHTTPResponse(
            url: url,
            statusCode: 200,
            headers: ["vary": "accept-language"],
            body: Data("fresh".utf8)
        )
        let client = RecordingWebHTTPClient(responses: [response, response])
        let fetcher = PolicyEnforcedWebDocumentFetcher(
            client: client,
            policy: TrustedOriginsWebURLPolicy(origins: [
                try WebOrigin(scheme: "https", host: "allowed.example")
            ])
        )

        _ = try await fetcher.fetch(WebDocumentRequest(url: url))
        _ = try await fetcher.fetch(WebDocumentRequest(url: url))

        #expect(await client.requestCount() == 2)
    }

    @Test("Responses requiring Expires interpretation are not cached", .timeLimit(.minutes(1)))
    func expiringResponseIsNotCached() async throws {
        let url = try #require(URL(string: "https://allowed.example/data"))
        let response = WebHTTPResponse(
            url: url,
            statusCode: 200,
            headers: ["expires": "Thu, 01 Jan 1970 00:00:00 GMT"],
            body: Data("stale".utf8)
        )
        let client = RecordingWebHTTPClient(responses: [response, response])
        let fetcher = PolicyEnforcedWebDocumentFetcher(
            client: client,
            policy: TrustedOriginsWebURLPolicy(origins: [
                try WebOrigin(scheme: "https", host: "allowed.example")
            ])
        )

        _ = try await fetcher.fetch(WebDocumentRequest(url: url))
        _ = try await fetcher.fetch(WebDocumentRequest(url: url))

        #expect(await client.requestCount() == 2)
    }

    @Test("Age consumes cache freshness", .timeLimit(.minutes(1)))
    func responseAgeConsumesFreshness() async throws {
        let url = try #require(URL(string: "https://allowed.example/data"))
        let response = WebHTTPResponse(
            url: url,
            statusCode: 200,
            headers: ["cache-control": "max-age=60", "age": "60"],
            body: Data("stale".utf8)
        )
        let client = RecordingWebHTTPClient(responses: [response, response])
        let fetcher = PolicyEnforcedWebDocumentFetcher(
            client: client,
            policy: TrustedOriginsWebURLPolicy(origins: [
                try WebOrigin(scheme: "https", host: "allowed.example")
            ])
        )

        _ = try await fetcher.fetch(WebDocumentRequest(url: url))
        _ = try await fetcher.fetch(WebDocumentRequest(url: url))

        #expect(await client.requestCount() == 2)
    }

    @Test("Bracketed IPv6 loopback has canonical origin")
    func bracketedIPv6LoopbackIsCanonicalized() throws {
        let bracketed = try WebOrigin(scheme: "http", host: "[::1]")
        let canonical = try WebOrigin(scheme: "http", host: "::1")

        #expect(bracketed == canonical)
        #expect(bracketed.description == "http://[::1]")
    }

    @Test("Negative redirect limits fail before network I/O", .timeLimit(.minutes(1)))
    func negativeRedirectLimitFailsClosed() async throws {
        let url = try #require(URL(string: "https://allowed.example/data"))
        let client = RecordingWebHTTPClient(responses: [])
        let fetcher = PolicyEnforcedWebDocumentFetcher(
            client: client,
            policy: TrustedOriginsWebURLPolicy(origins: [
                try WebOrigin(scheme: "https", host: "allowed.example")
            ]),
            maximumRedirects: -1
        )

        await #expect(throws: WebHTTPError.self) {
            _ = try await fetcher.fetch(WebDocumentRequest(url: url))
        }
        #expect(await client.requestCount() == 0)
    }

    @Test("Partial cache disabling is rejected", .timeLimit(.minutes(1)))
    func partialCacheConfigurationFailsClosed() async throws {
        let url = try #require(URL(string: "https://allowed.example/data"))
        let client = RecordingWebHTTPClient(responses: [])
        let fetcher = PolicyEnforcedWebDocumentFetcher(
            client: client,
            policy: TrustedOriginsWebURLPolicy(origins: [
                try WebOrigin(scheme: "https", host: "allowed.example")
            ]),
            cacheConfiguration: WebDocumentCacheConfiguration(
                timeToLive: 0,
                maximumEntries: 1,
                maximumTotalBodyBytes: 1
            )
        )

        await #expect(throws: WebHTTPError.self) {
            _ = try await fetcher.fetch(WebDocumentRequest(url: url))
        }
        #expect(await client.requestCount() == 0)
    }

    @Test("Domain filters use DNS label boundaries", .timeLimit(.minutes(1)))
    func domainFilterUsesLabelBoundaries() throws {
        let filter = try WebDomainFilter(
            allowedDomains: ["example.com"],
            blockedDomains: ["private.example.com"]
        )

        #expect(filter.allows(host: "example.com"))
        #expect(filter.allows(host: "docs.example.com"))
        #expect(!filter.allows(host: "private.example.com"))
        #expect(!filter.allows(host: "notexample.com"))
        #expect(!filter.allows(host: "example.com.attacker.invalid"))
    }

    @Test("DuckDuckGo redirect links are decoded as result URLs", .timeLimit(.minutes(1)))
    func duckDuckGoResultRedirectIsDecoded() throws {
        let html = """
            <a class="result__a" href="/l/?uddg=https%3A%2F%2Fdocs.example.com%2Fguide">Documentation</a>
            """

        let results = try DuckDuckGoHTMLParser.parse(html, limit: 10)

        #expect(results.count == 1)
        #expect(results.first?.url.absoluteString == "https://docs.example.com/guide")
    }
}

private actor RecordingWebHTTPClient: WebHTTPClient {
    private var responses: [WebHTTPResponse]
    private var requests: [WebHTTPRequest] = []

    init(responses: [WebHTTPResponse]) {
        self.responses = responses
    }

    func execute(_ request: WebHTTPRequest) async throws -> WebHTTPResponse {
        requests.append(request)
        guard !responses.isEmpty else {
            throw WebHTTPError.transport("No test response configured")
        }
        return responses.removeFirst()
    }

    func requestCount() -> Int {
        requests.count
    }

    func recordedRequests() -> [WebHTTPRequest] {
        requests
    }
}

private struct SuspendingWebHTTPClient: WebHTTPClient {
    func execute(_ request: WebHTTPRequest) async throws -> WebHTTPResponse {
        try await Task.sleep(for: .seconds(60))
        throw WebHTTPError.transport("Unexpected suspension completion")
    }
}

private struct SuspendingWebURLPolicy: WebURLPolicy {
    func authorize(_ url: URL) async throws -> AuthorizedWebURL {
        try await Task.sleep(for: .seconds(60))
        return AuthorizedWebURL(
            url: url,
            policyIdentifier: "suspending-test-policy"
        )
    }
}

private actor MutableWebURLPolicy: WebURLPolicy {
    private var origins: Set<WebOrigin>

    init(origins: Set<WebOrigin>) {
        self.origins = origins
    }

    func authorize(_ url: URL) async throws -> AuthorizedWebURL {
        let origin = try WebOrigin(url: url)
        guard origins.contains(origin) else {
            throw WebHTTPError.originNotAuthorized(origin.description)
        }
        return AuthorizedWebURL(
            url: url,
            policyIdentifier: "mutable-test-policy"
        )
    }

    func remove(_ origin: WebOrigin) {
        origins.remove(origin)
    }
}
