public struct InboundInvocationRequest: Sendable, Hashable {
    public let binding: VerifiedParticipantBinding
    public let envelope: SymbioInvocationEnvelope
    public let recipient: ParticipantDescriptor

    public init(
        binding: VerifiedParticipantBinding,
        envelope: SymbioInvocationEnvelope,
        recipient: ParticipantDescriptor
    ) {
        self.binding = binding
        self.envelope = envelope
        self.recipient = recipient
    }
}
