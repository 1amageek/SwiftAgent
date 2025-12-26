// MARK: - ProcessHandshake
// Handshake protocol for inter-process agent communication

import Foundation

// MARK: - AgentHandshakeInfo

/// Handshake information exchanged when spawning a process agent
///
/// When a parent process spawns a child agent process, they perform
/// a handshake to exchange metadata about the agent's capabilities.
///
/// Usage:
/// ```swift
/// // Parent side: Wait for handshake after spawning
/// let info = try await performHandshake(socketPath: socketPath)
///
/// // Child side: Send handshake on startup
/// let info = AgentHandshakeInfo(
///     id: myID,
///     name: "WorkerAgent",
///     accepts: ["work", "control"],
///     provides: ["result"]
/// )
/// try await sendHandshake(info, to: socketPath)
/// ```
public struct AgentHandshakeInfo: Codable, Sendable {
    /// Unique identifier for the agent
    public let id: String

    /// Human-readable display name
    public let name: String?

    /// Perception identifiers this agent accepts
    public let accepts: [String]

    /// Capability identifiers this agent provides
    public let provides: [String]

    /// Protocol version for compatibility checking
    public let protocolVersion: Int

    /// Additional metadata
    public let metadata: [String: String]

    public init(
        id: String,
        name: String? = nil,
        accepts: [String] = [],
        provides: [String] = [],
        protocolVersion: Int = 1,
        metadata: [String: String] = [:]
    ) {
        self.id = id
        self.name = name
        self.accepts = accepts
        self.provides = provides
        self.protocolVersion = protocolVersion
        self.metadata = metadata
    }
}

// MARK: - HandshakeRequest

/// Request sent from parent to child during handshake
public struct HandshakeRequest: Codable, Sendable {
    /// Parent's community ID
    public let parentID: String

    /// Protocol version expected by parent
    public let protocolVersion: Int

    public init(parentID: String, protocolVersion: Int = 1) {
        self.parentID = parentID
        self.protocolVersion = protocolVersion
    }
}

// MARK: - HandshakeResponse

/// Response from child to parent during handshake
public struct HandshakeResponse: Codable, Sendable {
    /// Whether handshake was successful
    public let success: Bool

    /// Agent information (if successful)
    public let agentInfo: AgentHandshakeInfo?

    /// Error message (if failed)
    public let errorMessage: String?

    public init(agentInfo: AgentHandshakeInfo) {
        self.success = true
        self.agentInfo = agentInfo
        self.errorMessage = nil
    }

    public init(error: String) {
        self.success = false
        self.agentInfo = nil
        self.errorMessage = error
    }
}

// MARK: - ProcessHandshakeError

/// Errors during process handshake
public enum ProcessHandshakeError: Error, LocalizedError {
    case connectionFailed(String)
    case handshakeFailed(String)
    case protocolMismatch(expected: Int, actual: Int)
    case timeout
    case invalidResponse

    public var errorDescription: String? {
        switch self {
        case .connectionFailed(let message):
            return "Connection failed: \(message)"
        case .handshakeFailed(let message):
            return "Handshake failed: \(message)"
        case .protocolMismatch(let expected, let actual):
            return "Protocol version mismatch: expected \(expected), got \(actual)"
        case .timeout:
            return "Handshake timed out"
        case .invalidResponse:
            return "Invalid handshake response"
        }
    }
}

// MARK: - ProcessHandshake Protocol

/// Protocol for types that can perform process handshakes
public protocol ProcessHandshake {
    /// Perform handshake as parent (waiting for child)
    func performHandshake(socketPath: String, timeout: Duration) async throws -> AgentHandshakeInfo

    /// Perform handshake as child (connecting to parent)
    func respondToHandshake(socketPath: String, agentInfo: AgentHandshakeInfo) async throws
}
