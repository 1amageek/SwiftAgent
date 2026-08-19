import Foundation

public enum AgentSessionError: Error, LocalizedError, Sendable {
    case connectionAlreadyConsumed
    case approvalRequiresConcurrentReceive
    case requestQueueFull(Int)
    case eventDeliveryFailed(String)
    case sessionAndShutdownFailed(session: String, shutdown: String)

    public var errorDescription: String? {
        switch self {
        case .connectionAlreadyConsumed:
            "An AgentSession owns a single connection run and cannot be run again"
        case .approvalRequiresConcurrentReceive:
            "A non-concurrent Agent connection requires a TurnGatedApprovalHandler that shares no competing input reader"
        case .requestQueueFull(let capacity):
            "The Agent request queue reached its capacity of \(capacity)"
        case .eventDeliveryFailed(let reason):
            "Failed to deliver an Agent event: \(reason)"
        case .sessionAndShutdownFailed(let session, let shutdown):
            "Agent session failed (\(session)); connection shutdown also failed (\(shutdown))"
        }
    }
}
