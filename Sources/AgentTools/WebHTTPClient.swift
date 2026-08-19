/// Performs exactly one HTTP request without following redirects.
///
/// A conforming client must return the same URL that it received in the
/// request and must enforce `maximumBodyBytes` while reading the body. It must
/// also cancel owned network work and return only after that work is drained
/// when the calling task is cancelled.
public protocol WebHTTPClient: Sendable {
    func execute(_ request: WebHTTPRequest) async throws -> WebHTTPResponse
}
