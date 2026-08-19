import Foundation
import SwiftAgentSymbio

public enum PeerConnectivitySymbioError: Error, LocalizedError, Sendable {
    case invalidConfiguration(String)
    case invalidLifecycle(String)
    case concurrentReceive
    case eventBufferFull(Int)
    case operationCapacityExceeded(Int)
    case peerUnavailable(TransportPeerID)
    case replyContextUnavailable(String)
    case invalidLocalCatalog(String)
    case invalidWireMessage(String)
    case wireMessageTooLarge(actual: Int, maximum: Int)
    case timeout
    case deadlineFailed(String)
    case backendFailed(String)
    case cleanupFailed([String])

    public var errorDescription: String? {
        switch self {
        case .invalidConfiguration(let reason):
            return "Invalid PeerConnectivity Symbio configuration: \(reason)"
        case .invalidLifecycle(let reason):
            return "Invalid PeerConnectivity Symbio link lifecycle: \(reason)"
        case .concurrentReceive:
            return "PeerConnectivity Symbio link supports exactly one receive owner"
        case .eventBufferFull(let capacity):
            return "PeerConnectivity Symbio link event buffer exceeded capacity \(capacity)"
        case .operationCapacityExceeded(let capacity):
            return "PeerConnectivity Symbio link reached its concurrent operation capacity of \(capacity)"
        case .peerUnavailable(let peerID):
            return "Transport peer '\(peerID.rawValue)' is unavailable"
        case .replyContextUnavailable(let contextID):
            return "Reply context '\(contextID)' is unavailable"
        case .invalidLocalCatalog(let reason):
            return "Invalid local participant catalog: \(reason)"
        case .invalidWireMessage(let reason):
            return "Invalid Symbio wire message: \(reason)"
        case .wireMessageTooLarge(let actual, let maximum):
            return "Symbio wire message size \(actual) exceeds maximum \(maximum)"
        case .timeout:
            return "PeerConnectivity Symbio operation timed out"
        case .deadlineFailed(let reason):
            return "PeerConnectivity Symbio deadline failed: \(reason)"
        case .backendFailed(let reason):
            return "PeerConnectivity backend failed: \(reason)"
        case .cleanupFailed(let failures):
            return "PeerConnectivity Symbio cleanup failed: \(failures.joined(separator: "; "))"
        }
    }
}
