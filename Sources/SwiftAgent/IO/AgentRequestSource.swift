/// Supplies application-level requests to an ``AgentSession``.
///
/// Framing, serialization, sockets, and server routing belong to concrete
/// adapters outside the Agent runtime. Returning `nil` means clean input EOF;
/// connection and decoding failures must be thrown.
public protocol AgentRequestSource: Sendable {
    /// Whether requests can be received while a turn is executing.
    var supportsConcurrentReceive: Bool { get }

    /// Returns the next request, or `nil` after a clean input EOF.
    func receive() async throws -> RunRequest?
}

extension AgentRequestSource {
    public var supportsConcurrentReceive: Bool { true }
}
