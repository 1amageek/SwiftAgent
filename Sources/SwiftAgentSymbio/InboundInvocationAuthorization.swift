public protocol InboundInvocationAuthorizer: Sendable {
    /// Decides one inbound invocation. Implementations must observe task
    /// cancellation so runtime shutdown can drain authorization work.
    func authorize(_ request: InboundInvocationRequest) async throws -> InboundInvocationDecision
}
