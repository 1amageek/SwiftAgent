/// Writes application-level events produced by an ``AgentSession``.
public protocol AgentEventWriter: Sendable {
    /// Writes one event or throws when delivery cannot be completed.
    func send(_ event: RunEvent) async throws
}
