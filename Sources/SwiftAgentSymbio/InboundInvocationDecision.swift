public enum InboundInvocationDecision: Sendable, Hashable {
    case allow
    case deny(reason: String)
}
