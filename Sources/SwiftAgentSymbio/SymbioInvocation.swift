public struct SymbioInvocation: Sendable, Hashable {
    public let envelope: SymbioInvocationEnvelope
    public let principal: SymbioInvocationPrincipal

    public init(
        envelope: SymbioInvocationEnvelope,
        principal: SymbioInvocationPrincipal
    ) {
        self.envelope = envelope
        self.principal = principal
    }
}
