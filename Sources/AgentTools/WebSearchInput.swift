import SwiftAgent

@Generable
public struct WebSearchInput: Sendable {
    @Guide(description: "Search query")
    public let query: String

    @Guide(description: "JSON array of exact domain suffixes permitted in results")
    public let allowedDomains: String

    @Guide(description: "JSON array of exact domain suffixes denied in results")
    public let blockedDomains: String

    @Guide(description: "Number of results to return, from one through fifty")
    public let limit: Int
}
