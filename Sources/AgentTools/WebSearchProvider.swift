public protocol WebSearchProvider: Sendable {
    func search(query: String, limit: Int) async throws -> [WebSearchResult]
}
