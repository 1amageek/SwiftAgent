import Foundation

public struct PolicyEnforcedWebDocumentFetcher: WebDocumentFetching {
    private let client: any WebHTTPClient
    private let policy: any WebURLPolicy
    private let maximumRedirects: Int
    private let cacheConfiguration: WebDocumentCacheConfiguration
    private let cache: WebDocumentCache

    public init(
        client: any WebHTTPClient,
        policy: any WebURLPolicy,
        maximumRedirects: Int = 5,
        cacheConfiguration: WebDocumentCacheConfiguration = .init()
    ) {
        self.client = client
        self.policy = policy
        self.maximumRedirects = maximumRedirects
        self.cacheConfiguration = cacheConfiguration
        self.cache = WebDocumentCache(configuration: cacheConfiguration)
    }

    public func fetch(_ request: WebDocumentRequest) async throws -> WebDocument {
        guard request.maximumBodyBytes > 0 else {
            throw WebHTTPError.invalidBodyLimit(request.maximumBodyBytes)
        }
        guard request.timeout > .zero else {
            throw WebHTTPError.invalidTimeout
        }
        guard maximumRedirects >= 0 else {
            throw WebHTTPError.invalidRedirectLimit(maximumRedirects)
        }
        try cacheConfiguration.validate()
        let deadline = ContinuousClock.now.advanced(by: request.timeout)
        try WebRequestHeaderPolicy.validate(request.headers)
        let original = try await authorize(request.url, before: deadline)
        let canCache = request.headers.isEmpty
        if canCache, let cached = await cache.get(original) {
            let reauthorizedFinalURL = try await authorize(
                cached.finalURL,
                before: deadline
            )
            guard reauthorizedFinalURL.url == cached.finalURL else {
                throw WebHTTPError.responseURLMismatch(
                    expected: cached.finalURL.absoluteString,
                    actual: reauthorizedFinalURL.url.absoluteString
                )
            }
            guard cached.body.count <= request.maximumBodyBytes else {
                throw WebHTTPError.responseTooLarge(
                    actual: Int64(cached.body.count),
                    maximum: request.maximumBodyBytes
                )
            }
            return cached
        }

        var current = original
        var headers = request.headers
        var redirectCount = 0

        while true {
            try Task.checkCancellation()
            let remaining = ContinuousClock.now.duration(to: deadline)
            guard remaining > .zero else {
                throw WebHTTPError.deadlineExceeded
            }
            let client = self.client
            let httpRequest = WebHTTPRequest(
                url: current.url,
                headers: headers,
                timeout: remaining,
                maximumBodyBytes: request.maximumBodyBytes
            )
            let response = try await withWebDeadline(remaining) {
                try await client.execute(httpRequest)
            }
            guard ContinuousClock.now < deadline else {
                throw WebHTTPError.deadlineExceeded
            }
            guard response.url == current.url else {
                throw WebHTTPError.responseURLMismatch(
                    expected: current.url.absoluteString,
                    actual: response.url.absoluteString
                )
            }
            guard response.body.count <= request.maximumBodyBytes else {
                throw WebHTTPError.responseTooLarge(
                    actual: Int64(response.body.count),
                    maximum: request.maximumBodyBytes
                )
            }
            guard Self.redirectStatuses.contains(response.statusCode) else {
                let document = WebDocument(
                    requestedURL: original.url,
                    finalURL: response.url,
                    statusCode: response.statusCode,
                    headers: response.headers,
                    body: response.body,
                    redirectCount: redirectCount,
                    isFromCache: false
                )
                if canCache,
                   (200..<300).contains(response.statusCode) {
                    await cache.insert(document, for: original)
                }
                return document
            }

            guard redirectCount < maximumRedirects else {
                throw WebHTTPError.redirectLimitExceeded(maximumRedirects)
            }
            guard let location = response.headers["location"],
                  let redirectURL = URL(
                    string: location,
                    relativeTo: current.url
                  )?.absoluteURL else {
                throw WebHTTPError.redirectMissingLocation(response.statusCode)
            }

            let next = try await authorize(redirectURL, before: deadline)
            if try WebOrigin(url: next.url) != WebOrigin(url: current.url) {
                headers.removeAll()
            }
            current = next
            redirectCount += 1
        }
    }

    private static let redirectStatuses: Set<Int> = [301, 302, 303, 307, 308]

    private func authorize(
        _ url: URL,
        before deadline: ContinuousClock.Instant
    ) async throws -> AuthorizedWebURL {
        let remaining = ContinuousClock.now.duration(to: deadline)
        guard remaining > .zero else {
            throw WebHTTPError.deadlineExceeded
        }
        let policy = self.policy
        return try await withWebDeadline(remaining) {
            try await policy.authorize(url)
        }
    }
}
