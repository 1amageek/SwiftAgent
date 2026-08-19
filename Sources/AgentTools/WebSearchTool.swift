import Foundation
import SwiftAgent

public struct WebSearchTool: Tool {
    private static let maximumQueryCharacters = 4_096

    public typealias Arguments = WebSearchInput
    public typealias Output = WebSearchOutput

    public static let name = "WebSearch"
    public var name: String { Self.name }

    public static let description = """
        Search the web through the configured provider. Domain allow and deny
        filters are enforced on parsed result hosts using DNS label boundaries.
        Fetch full result content separately with WebFetch.
        """

    public var description: String { Self.description }
    public var parameters: GenerationSchema { WebSearchInput.generationSchema }

    private let provider: any WebSearchProvider

    public init(provider: any WebSearchProvider) {
        self.provider = provider
    }

    public func call(arguments: WebSearchInput) async throws -> WebSearchOutput {
        try Task.checkCancellation()
        try TurnCancellationContext.current?.checkCancellation()
        let query = arguments.query.trimmingCharacters(
            in: .whitespacesAndNewlines
        )
        guard !query.isEmpty else {
            throw WebSearchError.emptyQuery
        }
        guard query.count <= Self.maximumQueryCharacters else {
            throw WebSearchError.queryTooLong(
                actual: query.count,
                maximum: Self.maximumQueryCharacters
            )
        }
        guard (1...50).contains(arguments.limit) else {
            throw WebSearchError.invalidLimit(arguments.limit)
        }

        let filter = try WebDomainFilter(
            allowedDomains: parseDomainList(arguments.allowedDomains),
            blockedDomains: parseDomainList(arguments.blockedDomains)
        )
        let providerResults = try await provider.search(
            query: query,
            limit: arguments.limit
        )
        var results: [WebSearchResult] = []
        results.reserveCapacity(arguments.limit)
        for result in providerResults {
            guard let scheme = result.url.scheme?.lowercased(),
                  scheme == "https" || scheme == "http",
                  let host = result.url.host,
                  result.url.user == nil,
                  result.url.password == nil else {
                throw WebSearchError.invalidProviderResult(
                    result.url.absoluteString
                )
            }
            if filter.allows(host: host) {
                results.append(result)
            }
            if results.count == arguments.limit {
                break
            }
        }
        return WebSearchOutput(results: results, query: query)
    }

    private func parseDomainList(_ json: String) throws -> [String] {
        let trimmed = json.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            return []
        }
        guard let data = trimmed.data(using: .utf8) else {
            throw WebSearchError.invalidDomainList(json)
        }
        do {
            return try JSONDecoder().decode([String].self, from: data)
        } catch {
            throw WebSearchError.invalidDomainList(json)
        }
    }
}
