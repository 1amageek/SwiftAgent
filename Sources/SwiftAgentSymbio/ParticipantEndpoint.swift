import NetworkingCore

public protocol ParticipantEndpoint: Actor {
    nonisolated var descriptor: ParticipantDescriptor { get }

    /// Executes one invocation and cooperatively observes task cancellation.
    func invoke(_ invocation: SymbioInvocation) async throws -> OwnedBytes?

    /// Rejects new work and does not return until owned invocations are drained.
    func shutdown() async
}
