import Foundation

public struct DuckDuckGoSearchProvider: WebSearchProvider {
    private let fetcher: any WebDocumentFetching

    public init(fetcher: any WebDocumentFetching) {
        self.fetcher = fetcher
    }

    public static func live(
        client: any WebHTTPClient = URLSessionWebHTTPClient()
    ) throws -> Self {
        let origins: Set<WebOrigin> = [
            try WebOrigin(scheme: "https", host: "html.duckduckgo.com"),
            try WebOrigin(scheme: "https", host: "duckduckgo.com"),
        ]
        return Self(fetcher: PolicyEnforcedWebDocumentFetcher(
            client: client,
            policy: TrustedOriginsWebURLPolicy(
                origins: origins,
                policyIdentifier: "duckduckgo-search"
            ),
            maximumRedirects: 2,
            cacheConfiguration: .init(
                timeToLive: 60,
                maximumEntries: 16,
                maximumTotalBodyBytes: 4 * 1_024 * 1_024
            )
        ))
    }

    public func search(
        query: String,
        limit: Int
    ) async throws -> [WebSearchResult] {
        var components = URLComponents()
        components.scheme = "https"
        components.host = "html.duckduckgo.com"
        components.path = "/html/"
        components.queryItems = [URLQueryItem(name: "q", value: query)]
        guard let url = components.url else {
            throw WebSearchError.invalidProviderResult("search URL")
        }

        let document = try await fetcher.fetch(WebDocumentRequest(
            url: url,
            timeout: .seconds(20),
            maximumBodyBytes: 2 * 1_024 * 1_024
        ))
        guard (200..<300).contains(document.statusCode) else {
            throw WebSearchError.providerHTTPStatus(document.statusCode)
        }
        guard let html = String(data: document.body, encoding: .utf8) else {
            throw WebSearchError.invalidProviderEncoding
        }
        return try DuckDuckGoHTMLParser.parse(html, limit: limit)
    }
}
