public struct RejectingInboundInvocationAuthorizer: InboundInvocationAuthorizer {
    public init() {}

    public func authorize(
        _ request: InboundInvocationRequest
    ) async throws -> InboundInvocationDecision {
        .deny(reason: "No inbound invocation authorizer is configured")
    }
}
