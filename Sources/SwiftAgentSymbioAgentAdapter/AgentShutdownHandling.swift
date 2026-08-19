public protocol AgentShutdownHandling: Actor {
    /// Rejects new agent work and releases or cancels work already owned by the
    /// agent. The endpoint invokes this before waiting for invocation drain.
    func shutdown() async
}
