public enum SymbioInvocationPrincipal: Sendable, Hashable {
    case local(ParticipantDescriptor)
    case remote(VerifiedParticipantBinding)

    public var descriptor: ParticipantDescriptor {
        switch self {
        case .local(let descriptor):
            return descriptor
        case .remote(let binding):
            return binding.descriptor
        }
    }
}
