import Foundation

/// Errors defined by the application-level connection boundary.
public enum AgentConnectionError: Error, LocalizedError, Sendable {
    case inputClosed
    case outputClosed
    case encodingFailed(String)
    case decodingFailed(String)
    case inputBufferFull(Int)
    case inputReadFailed(String)
    case inputCloseFailed(String)
    case outputWriteFailed(String)
    case invalidState(String)

    public var errorDescription: String? {
        switch self {
        case .inputClosed:
            "The Agent connection input is closed"
        case .outputClosed:
            "The Agent connection output is closed"
        case .encodingFailed(let reason):
            "Failed to encode Agent connection data: \(reason)"
        case .decodingFailed(let reason):
            "Failed to decode Agent connection data: \(reason)"
        case .inputBufferFull(let capacity):
            "The Agent connection input buffer reached its capacity of \(capacity)"
        case .inputReadFailed(let reason):
            "Failed to read Agent connection input: \(reason)"
        case .inputCloseFailed(let reason):
            "Failed to close Agent connection input: \(reason)"
        case .outputWriteFailed(let reason):
            "Failed to write Agent connection output: \(reason)"
        case .invalidState(let reason):
            "Invalid Agent connection state: \(reason)"
        }
    }
}
