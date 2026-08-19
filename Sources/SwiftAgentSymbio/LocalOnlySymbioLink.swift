public actor LocalOnlySymbioLink: SymbioLink {
    private enum State {
        case idle
        case running
        case finished
    }

    private var state = State.idle
    private var receiver: CheckedContinuation<SymbioLinkEvent?, any Error>?

    public init() {}

    public func start() async throws {
        guard case .idle = state else {
            throw SymbioRuntimeError.invalidLifecycle("The local-only link cannot be started twice")
        }
        state = .running
    }

    public func synchronizeLocalParticipants(
        _ descriptors: [ParticipantDescriptor]
    ) async throws {}

    public func receive() async throws -> SymbioLinkEvent? {
        guard case .running = state else {
            if case .finished = state {
                return nil
            }
            throw SymbioRuntimeError.invalidLifecycle("The local-only link is not running")
        }
        guard receiver == nil else {
            throw SymbioRuntimeError.invalidLifecycle("SymbioLink supports exactly one receive owner")
        }
        return try await withCheckedThrowingContinuation { continuation in
            receiver = continuation
        }
    }

    public func invoke(
        _ envelope: SymbioInvocationEnvelope,
        on transportPeerID: TransportPeerID,
        timeout: Duration
    ) async throws -> SymbioInvocationReply {
        throw SymbioRuntimeError.noLinkAvailable
    }

    public func send(
        _ reply: SymbioInvocationReply,
        to context: SymbioReplyContext
    ) async throws {
        throw SymbioRuntimeError.noLinkAvailable
    }

    public func shutdown() async throws {
        guard case .finished = state else {
            state = .finished
            let receiver = self.receiver
            self.receiver = nil
            receiver?.resume(returning: nil)
            return
        }
    }
}
