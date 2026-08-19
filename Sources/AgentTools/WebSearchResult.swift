import Foundation

public struct WebSearchResult: Sendable, Hashable {
    public let title: String
    public let url: URL
    public let snippet: String

    public init(title: String, url: URL, snippet: String) {
        self.title = title
        self.url = url
        self.snippet = snippet
    }

    public var domain: String {
        url.host.map(WebOrigin.normalize) ?? ""
    }

    public var markdownLink: String {
        let escapedTitle = title
            .replacingOccurrences(of: "[", with: "\\[")
            .replacingOccurrences(of: "]", with: "\\]")
        return "[\(escapedTitle)](\(url.absoluteString))"
    }
}
