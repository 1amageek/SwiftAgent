public struct AllowingInboundInvocationAuthorizer: InboundInvocationAuthorizer {
    public init() {}

    public func authorize(
        _ request: InboundInvocationRequest
    ) async throws -> InboundInvocationDecision {
        .allow
    }
}
