//
//  RunEvent.swift
//  SwiftAgent
//

import Foundation

/// A structured event emitted during an Agent run.
///
/// `RunEvent` is the canonical event type for the Agent I/O contract.
/// Each case carries exactly the payload required for that event kind.
/// Transport adapters serialize/deserialize this enum for their wire format.
///
/// The event stream for a typical turn looks like:
///
/// ```
/// runStarted
///   → tokenDelta (repeated)
///   → toolCall → approvalRequired → approvalResolved → toolResult
///   → tokenDelta (repeated)
/// runCompleted
/// ```
public enum RunEvent: Sendable, Codable {

    /// The run has started processing.
    case runStarted(RunStarted)

    /// A token (or chunk of text) has been generated.
    case tokenDelta(TokenDelta)

    /// The LLM is requesting a tool call.
    case toolCall(ToolCallEvent)

    /// A tool call has completed.
    case toolResult(ToolResultEvent)

    /// A tool call requires user approval before proceeding.
    case approvalRequired(ApprovalRequestEvent)

    /// An approval request has been resolved.
    case approvalResolved(ApprovalResolvedEvent)

    /// A non-fatal warning.
    case warning(WarningEvent)

    /// An error occurred (may or may not be fatal).
    case error(RunError)

    /// The run has completed.
    case runCompleted(RunCompleted)
}

// MARK: - Codable

extension RunEvent {

    private enum CodingKeys: String, CodingKey {
        case type, payload
    }

    private enum EventType: String, Codable {
        case runStarted, tokenDelta, toolCall, toolResult
        case approvalRequired, approvalResolved
        case warning, error, runCompleted
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let type = try container.decode(EventType.self, forKey: .type)
        switch type {
        case .runStarted:
            self = .runStarted(try container.decode(RunStarted.self, forKey: .payload))
        case .tokenDelta:
            self = .tokenDelta(try container.decode(TokenDelta.self, forKey: .payload))
        case .toolCall:
            self = .toolCall(try container.decode(ToolCallEvent.self, forKey: .payload))
        case .toolResult:
            self = .toolResult(try container.decode(ToolResultEvent.self, forKey: .payload))
        case .approvalRequired:
            self = .approvalRequired(try container.decode(ApprovalRequestEvent.self, forKey: .payload))
        case .approvalResolved:
            self = .approvalResolved(try container.decode(ApprovalResolvedEvent.self, forKey: .payload))
        case .warning:
            self = .warning(try container.decode(WarningEvent.self, forKey: .payload))
        case .error:
            self = .error(try container.decode(RunError.self, forKey: .payload))
        case .runCompleted:
            self = .runCompleted(try container.decode(RunCompleted.self, forKey: .payload))
        }
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        switch self {
        case .runStarted(let payload):
            try container.encode(EventType.runStarted, forKey: .type)
            try container.encode(payload, forKey: .payload)
        case .tokenDelta(let payload):
            try container.encode(EventType.tokenDelta, forKey: .type)
            try container.encode(payload, forKey: .payload)
        case .toolCall(let payload):
            try container.encode(EventType.toolCall, forKey: .type)
            try container.encode(payload, forKey: .payload)
        case .toolResult(let payload):
            try container.encode(EventType.toolResult, forKey: .type)
            try container.encode(payload, forKey: .payload)
        case .approvalRequired(let payload):
            try container.encode(EventType.approvalRequired, forKey: .type)
            try container.encode(payload, forKey: .payload)
        case .approvalResolved(let payload):
            try container.encode(EventType.approvalResolved, forKey: .type)
            try container.encode(payload, forKey: .payload)
        case .warning(let payload):
            try container.encode(EventType.warning, forKey: .type)
            try container.encode(payload, forKey: .payload)
        case .error(let payload):
            try container.encode(EventType.error, forKey: .type)
            try container.encode(payload, forKey: .payload)
        case .runCompleted(let payload):
            try container.encode(EventType.runCompleted, forKey: .type)
            try container.encode(payload, forKey: .payload)
        }
    }
}

// MARK: - Event Payloads

extension RunEvent {

    public struct RunStarted: Sendable, Codable {
        public let sessionID: String
        public let turnID: String
        public let timestamp: Date

        public init(sessionID: String, turnID: String, timestamp: Date = Date()) {
            self.sessionID = sessionID
            self.turnID = turnID
            self.timestamp = timestamp
        }
    }

    public struct TokenDelta: Sendable, Codable {
        /// The incremental text chunk.
        public let delta: String

        /// Accumulated text so far.
        public let accumulated: String

        /// Whether the underlying content stream is complete.
        public let isComplete: Bool

        public init(delta: String, accumulated: String, isComplete: Bool = false) {
            self.delta = delta
            self.accumulated = accumulated
            self.isComplete = isComplete
        }
    }

    public struct ToolCallEvent: Sendable, Codable {
        public let toolUseID: String
        public let toolName: String
        public let arguments: String
        public let sessionID: String
        public let turnID: String
        public let timestamp: Date

        public init(
            toolUseID: String = UUID().uuidString,
            toolName: String,
            arguments: String,
            sessionID: String,
            turnID: String,
            timestamp: Date = Date()
        ) {
            self.toolUseID = toolUseID
            self.toolName = toolName
            self.arguments = arguments
            self.sessionID = sessionID
            self.turnID = turnID
            self.timestamp = timestamp
        }
    }

    public struct ToolResultEvent: Sendable, Codable {
        public let toolUseID: String
        public let toolName: String
        public let output: String
        public let success: Bool
        public let duration: Duration
        public let exitCode: Int32?
        public let sessionID: String
        public let turnID: String
        public let timestamp: Date

        public init(
            toolUseID: String,
            toolName: String,
            output: String,
            success: Bool,
            duration: Duration,
            exitCode: Int32? = nil,
            sessionID: String,
            turnID: String,
            timestamp: Date = Date()
        ) {
            self.toolUseID = toolUseID
            self.toolName = toolName
            self.output = output
            self.success = success
            self.duration = duration
            self.exitCode = exitCode
            self.sessionID = sessionID
            self.turnID = turnID
            self.timestamp = timestamp
        }
    }

    public struct ApprovalRequestEvent: Sendable, Codable {
        public let approvalID: String
        public let toolName: String
        public let arguments: String
        public let operationDescription: String
        public let riskLevel: String
        public let sessionID: String
        public let turnID: String
        public let timestamp: Date

        public init(
            approvalID: String = UUID().uuidString,
            toolName: String,
            arguments: String,
            operationDescription: String,
            riskLevel: String,
            sessionID: String,
            turnID: String,
            timestamp: Date = Date()
        ) {
            self.approvalID = approvalID
            self.toolName = toolName
            self.arguments = arguments
            self.operationDescription = operationDescription
            self.riskLevel = riskLevel
            self.sessionID = sessionID
            self.turnID = turnID
            self.timestamp = timestamp
        }
    }

    public struct ApprovalResolvedEvent: Sendable, Codable {
        public let approvalID: String
        public let decision: ApprovalDecision
        public let sessionID: String
        public let turnID: String
        public let timestamp: Date

        public init(
            approvalID: String,
            decision: ApprovalDecision,
            sessionID: String,
            turnID: String,
            timestamp: Date = Date()
        ) {
            self.approvalID = approvalID
            self.decision = decision
            self.sessionID = sessionID
            self.turnID = turnID
            self.timestamp = timestamp
        }
    }

    public struct WarningEvent: Sendable, Codable {
        public let message: String
        public let code: String?
        public let sessionID: String
        public let turnID: String
        public let timestamp: Date

        public init(
            message: String,
            code: String? = nil,
            sessionID: String,
            turnID: String,
            timestamp: Date = Date()
        ) {
            self.message = message
            self.code = code
            self.sessionID = sessionID
            self.turnID = turnID
            self.timestamp = timestamp
        }
    }

    public struct RunError: Sendable, Codable {
        public let message: String
        public let code: String?
        public let isFatal: Bool
        public let underlyingError: (any Error)?
        public let sessionID: String
        public let turnID: String
        public let timestamp: Date

        enum CodingKeys: String, CodingKey {
            case message, code, isFatal, sessionID, turnID, timestamp
        }

        public init(
            message: String,
            code: String? = nil,
            isFatal: Bool = false,
            underlyingError: (any Error)? = nil,
            sessionID: String,
            turnID: String,
            timestamp: Date = Date()
        ) {
            self.message = message
            self.code = code
            self.isFatal = isFatal
            self.underlyingError = underlyingError
            self.sessionID = sessionID
            self.turnID = turnID
            self.timestamp = timestamp
        }

        public init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            self.message = try container.decode(String.self, forKey: .message)
            self.code = try container.decodeIfPresent(String.self, forKey: .code)
            self.isFatal = try container.decode(Bool.self, forKey: .isFatal)
            self.underlyingError = nil
            self.sessionID = try container.decode(String.self, forKey: .sessionID)
            self.turnID = try container.decode(String.self, forKey: .turnID)
            self.timestamp = try container.decode(Date.self, forKey: .timestamp)
        }

        public func encode(to encoder: Encoder) throws {
            var container = encoder.container(keyedBy: CodingKeys.self)
            try container.encode(message, forKey: .message)
            try container.encodeIfPresent(code, forKey: .code)
            try container.encode(isFatal, forKey: .isFatal)
            try container.encode(sessionID, forKey: .sessionID)
            try container.encode(turnID, forKey: .turnID)
            try container.encode(timestamp, forKey: .timestamp)
        }
    }

    public struct RunCompleted: Sendable, Codable {
        public let sessionID: String
        public let turnID: String
        public let status: RunStatus
        public let timestamp: Date

        public init(
            sessionID: String,
            turnID: String,
            status: RunStatus,
            timestamp: Date = Date()
        ) {
            self.sessionID = sessionID
            self.turnID = turnID
            self.status = status
            self.timestamp = timestamp
        }
    }
}
