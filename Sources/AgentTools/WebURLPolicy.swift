import Foundation

public protocol WebURLPolicy: Sendable {
    /// Authorizes and normalizes one URL before it reaches a network client.
    /// Implementations must cooperatively observe cancellation and drain owned
    /// work before returning from cancellation.
    func authorize(_ url: URL) async throws -> AuthorizedWebURL
}
