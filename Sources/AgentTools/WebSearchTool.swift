//
//  WebSearchTool.swift
//  SwiftAgent
//
//  Created by SwiftAgent on 2025/01/23.
//

import Foundation
import SwiftAgent

/// A tool for performing web searches and returning results.
///
/// `WebSearchTool` provides web search capabilities with domain filtering
/// and result formatting. Requires a search provider to be configured.
///
/// ## Features
/// - Web search with query string
/// - Domain filtering (allow/block specific domains)
/// - Formatted search results with titles, URLs, and snippets
/// - Configurable result limit
///
/// ## Usage
/// - Provide a search query
/// - Optionally filter by allowed or blocked domains
/// - Results include markdown-formatted links
///
/// ## Configuration
/// Requires a `WebSearchProvider` to be set. You can implement custom providers
/// for different search APIs (e.g., Google Custom Search, Bing, DuckDuckGo).
///
/// ## Limitations
/// - Results depend on the configured search provider
/// - Some providers may have rate limits or require API keys
public struct WebSearchTool: Tool {
    public typealias Arguments = WebSearchInput
    public typealias Output = WebSearchOutput

    public static let name = "WebSearch"
    public var name: String { Self.name }

    public static let description = """
    Search the web to find relevant URLs when you don't know the exact page. \
    Use for discovering information, finding solutions, or researching topics. \
    Returns list of results with titles, URLs, and snippets. \
    After finding URLs, use WebFetch to read full content.
    """

    public var description: String { Self.description }

    public var parameters: GenerationSchema {
        WebSearchInput.generationSchema
    }

    private let provider: WebSearchProvider

    /// Creates a WebSearchTool with the specified search provider.
    ///
    /// - Parameter provider: The search provider to use for queries.
    public init(provider: WebSearchProvider) {
        self.provider = provider
    }

    public func call(arguments: WebSearchInput) async throws -> WebSearchOutput {
        // Validate query
        guard !arguments.query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return WebSearchOutput(
                success: false,
                results: [],
                query: arguments.query,
                message: "Search query cannot be empty"
            )
        }

        // Parse domain filters
        let allowedDomains = parseDomainList(arguments.allowedDomains)
        let blockedDomains = parseDomainList(arguments.blockedDomains)

        // Perform search
        do {
            let searchResults = try await provider.search(
                query: arguments.query,
                limit: arguments.limit > 0 ? arguments.limit : 10,
                allowedDomains: allowedDomains,
                blockedDomains: blockedDomains
            )

            return WebSearchOutput(
                success: true,
                results: searchResults,
                query: arguments.query,
                message: "Found \(searchResults.count) result(s)"
            )
        } catch {
            return WebSearchOutput(
                success: false,
                results: [],
                query: arguments.query,
                message: "Search failed: \(error.localizedDescription)"
            )
        }
    }

    private func parseDomainList(_ json: String) -> [String] {
        guard !json.isEmpty, json != "[]" else { return [] }

        guard let data = json.data(using: .utf8),
              let domains = try? JSONDecoder().decode([String].self, from: data) else {
            return []
        }

        return domains
    }
}

// MARK: - Input/Output Types

/// Input structure for web search operations.
@Generable
public struct WebSearchInput: Sendable {
    @Guide(description: "The search query to use")
    public let query: String

    @Guide(description: "JSON array of domains to include in results (e.g., [\"github.com\", \"stackoverflow.com\"])")
    public let allowedDomains: String

    @Guide(description: "JSON array of domains to exclude from results")
    public let blockedDomains: String

    @Guide(description: "Maximum number of results to return. Defaults to 10.")
    public let limit: Int
}

/// A single search result.
public struct WebSearchResult: Sendable {
    /// The title of the search result.
    public let title: String

    /// The URL of the search result.
    public let url: String

    /// A snippet or description of the content.
    public let snippet: String

    /// The domain of the result.
    public let domain: String

    public init(title: String, url: String, snippet: String, domain: String) {
        self.title = title
        self.url = url
        self.snippet = snippet
        self.domain = domain
    }

    /// Returns the result formatted as a markdown link.
    public var markdownLink: String {
        "[\(title)](\(url))"
    }
}

/// Output structure for web search operations.
public struct WebSearchOutput: Sendable {
    /// Whether the search was successful.
    public let success: Bool

    /// The search results.
    public let results: [WebSearchResult]

    /// The original query.
    public let query: String

    /// A message about the search operation.
    public let message: String

    public init(success: Bool, results: [WebSearchResult], query: String, message: String) {
        self.success = success
        self.results = results
        self.query = query
        self.message = message
    }
}

extension WebSearchOutput: PromptRepresentable {
    public var promptRepresentation: Prompt {
        Prompt(description)
    }
}

extension WebSearchOutput: CustomStringConvertible {
    public var description: String {
        let status = success ? "Success" : "Failed"
        let header = """
        WebSearch [\(status)]
        Query: \(query)
        \(message)
        """

        if results.isEmpty {
            return header + "\n\nNo results found"
        }

        var output = header + "\n\nResults:"

        for (index, result) in results.enumerated() {
            output += "\n\n\(index + 1). \(result.markdownLink)"
            if !result.snippet.isEmpty {
                output += "\n   \(result.snippet)"
            }
        }

        output += "\n\nSources:"
        for result in results {
            output += "\n- \(result.markdownLink)"
        }

        return output
    }
}

// MARK: - Search Provider Protocol

/// A protocol for implementing web search providers.
///
/// Implement this protocol to connect different search APIs to WebSearchTool.
public protocol WebSearchProvider: Sendable {
    /// Performs a web search with the given parameters.
    ///
    /// - Parameters:
    ///   - query: The search query string.
    ///   - limit: Maximum number of results to return.
    ///   - allowedDomains: List of domains to include (empty means all domains).
    ///   - blockedDomains: List of domains to exclude.
    /// - Returns: An array of search results.
    func search(
        query: String,
        limit: Int,
        allowedDomains: [String],
        blockedDomains: [String]
    ) async throws -> [WebSearchResult]
}

// MARK: - Mock Search Provider (for testing)

/// A mock search provider that returns simulated results.
///
/// Use this for testing or as a template for implementing real providers.
public struct MockSearchProvider: WebSearchProvider {
    public init() {}

    public func search(
        query: String,
        limit: Int,
        allowedDomains: [String],
        blockedDomains: [String]
    ) async throws -> [WebSearchResult] {
        // Simulate some mock results
        let mockResults = [
            WebSearchResult(
                title: "Search Result 1 for: \(query)",
                url: "https://example.com/result1",
                snippet: "This is a mock search result for testing purposes.",
                domain: "example.com"
            ),
            WebSearchResult(
                title: "Search Result 2 for: \(query)",
                url: "https://docs.example.org/guide",
                snippet: "Another mock result with relevant information.",
                domain: "docs.example.org"
            ),
            WebSearchResult(
                title: "Search Result 3 for: \(query)",
                url: "https://blog.example.net/article",
                snippet: "A third mock result to demonstrate pagination.",
                domain: "blog.example.net"
            )
        ]

        // Filter by allowed domains
        var filtered = mockResults
        if !allowedDomains.isEmpty {
            filtered = filtered.filter { result in
                allowedDomains.contains { result.domain.contains($0) }
            }
        }

        // Filter by blocked domains
        if !blockedDomains.isEmpty {
            filtered = filtered.filter { result in
                !blockedDomains.contains { result.domain.contains($0) }
            }
        }

        // Apply limit
        return Array(filtered.prefix(limit))
    }
}

// MARK: - DuckDuckGo Search Provider

/// A search provider that uses DuckDuckGo's HTML search.
///
/// Note: This uses DuckDuckGo's HTML interface which may have rate limits.
/// For production use, consider using an official search API.
public struct DuckDuckGoSearchProvider: WebSearchProvider {
    private let urlFetcher: URLFetchTool

    public init() {
        self.urlFetcher = URLFetchTool()
    }

    public func search(
        query: String,
        limit: Int,
        allowedDomains: [String],
        blockedDomains: [String]
    ) async throws -> [WebSearchResult] {
        // Build search URL
        let encodedQuery = query.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? query
        var searchURL = "https://html.duckduckgo.com/html/?q=\(encodedQuery)"

        // Add site restriction if allowed domains specified
        if !allowedDomains.isEmpty {
            let siteFilter = allowedDomains.map { "site:\($0)" }.joined(separator: " OR ")
            let encodedFilter = siteFilter.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? siteFilter
            searchURL += "+\(encodedFilter)"
        }

        // Fetch search results page
        let fetchInputContent = GeneratedContent(properties: [
            "url": searchURL,
            "prompt": "Extract search results"
        ])
        let fetchInput = try FetchInput(fetchInputContent)
        let fetchResult = try await urlFetcher.call(arguments: fetchInput)

        guard fetchResult.success else {
            throw WebSearchError.fetchFailed(fetchResult.output)
        }

        // Parse results from HTML (simplified parsing)
        var results = parseSearchResults(from: fetchResult.output)

        // Filter by blocked domains
        if !blockedDomains.isEmpty {
            results = results.filter { result in
                !blockedDomains.contains { result.domain.contains($0) }
            }
        }

        return Array(results.prefix(limit))
    }

    private func parseSearchResults(from content: String) -> [WebSearchResult] {
        var results: [WebSearchResult] = []

        // Simple pattern matching for DuckDuckGo results
        // Look for markdown links created by HTML to Markdown conversion
        let linkPattern = "\\[([^\\]]+)\\]\\(([^)]+)\\)"
        guard let regex = try? NSRegularExpression(pattern: linkPattern, options: []) else {
            return results
        }

        let range = NSRange(content.startIndex..., in: content)
        let matches = regex.matches(in: content, options: [], range: range)

        for match in matches {
            guard match.numberOfRanges >= 3,
                  let titleRange = Range(match.range(at: 1), in: content),
                  let urlRange = Range(match.range(at: 2), in: content) else {
                continue
            }

            let title = String(content[titleRange])
            let url = String(content[urlRange])

            // Skip non-http links and DuckDuckGo internal links
            guard url.hasPrefix("http"),
                  !url.contains("duckduckgo.com") else {
                continue
            }

            // Extract domain
            let domain = URL(string: url)?.host ?? ""

            results.append(WebSearchResult(
                title: title,
                url: url,
                snippet: "",
                domain: domain
            ))
        }

        return results
    }
}

// MARK: - Errors

/// Errors that can occur during web search operations.
public enum WebSearchError: LocalizedError {
    case fetchFailed(String)
    case parsingFailed
    case rateLimited
    case providerError(String)

    public var errorDescription: String? {
        switch self {
        case .fetchFailed(let message):
            return "Failed to fetch search results: \(message)"
        case .parsingFailed:
            return "Failed to parse search results"
        case .rateLimited:
            return "Search rate limit exceeded"
        case .providerError(let message):
            return "Search provider error: \(message)"
        }
    }
}
