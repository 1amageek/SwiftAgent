import SwiftAgent

public struct WebSearchOutput: Sendable {
    public let results: [WebSearchResult]
    public let query: String

    public init(results: [WebSearchResult], query: String) {
        self.results = results
        self.query = query
    }
}

extension WebSearchOutput: PromptRepresentable {
    public var promptRepresentation: Prompt {
        Prompt(description)
    }
}

extension WebSearchOutput: CustomStringConvertible {
    public var description: String {
        var output = "WebSearch\nQuery: \(query)\nResults: \(results.count)"
        for (index, result) in results.enumerated() {
            output += "\n\n\(index + 1). \(result.markdownLink)"
            if !result.snippet.isEmpty {
                output += "\n   \(result.snippet)"
            }
        }
        return output
    }
}
