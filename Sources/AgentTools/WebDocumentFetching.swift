public protocol WebDocumentFetching: Sendable {
    func fetch(_ request: WebDocumentRequest) async throws -> WebDocument
}
