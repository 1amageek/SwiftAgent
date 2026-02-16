//
//  RunRequest.swift
//  SwiftAgent
//

import Foundation

/// The canonical input to an Agent run.
///
/// `RunRequest` represents a single turn in a conversation session.
/// It carries the input payload, optional context, execution policy,
/// and metadata for correlation across transports.
public struct RunRequest: Sendable, Codable {

    /// Unique identifier for the session.
    public let sessionID: String

    /// Unique identifier for this turn within the session.
    ///
    /// Used for idempotency — the runtime will not process the same turnID twice.
    public let turnID: String

    /// The input payload.
    public let input: InputPayload

    /// Additional context for this turn (e.g., steering messages).
    public let context: ContextPayload?

    /// Execution policy overrides for this turn.
    public let policy: ExecutionPolicy?

    /// Arbitrary metadata from the transport.
    public let metadata: [String: String]?

    public init(
        sessionID: String = UUID().uuidString,
        turnID: String = UUID().uuidString,
        input: InputPayload,
        context: ContextPayload? = nil,
        policy: ExecutionPolicy? = nil,
        metadata: [String: String]? = nil
    ) {
        self.sessionID = sessionID
        self.turnID = turnID
        self.input = input
        self.context = context
        self.policy = policy
        self.metadata = metadata
    }
}

// MARK: - InputPayload

/// The input payload carried by a RunRequest.
public enum InputPayload: Sendable, Codable {
    /// Plain text input (most common).
    case text(String)

    /// An approval response to a previous `approvalRequired` event.
    case approvalResponse(ApprovalResponse)

    /// A cancellation signal for the current turn.
    case cancel
}

// MARK: - ApprovalResponse

/// A response to an approval request, sent by the client via the transport.
public struct ApprovalResponse: Sendable, Codable {
    /// The approval ID that this response correlates with.
    public let approvalID: String

    /// The user's decision.
    public let decision: ApprovalDecision

    public init(approvalID: String, decision: ApprovalDecision) {
        self.approvalID = approvalID
        self.decision = decision
    }
}

/// The user's decision in response to an approval request.
public enum ApprovalDecision: String, Sendable, Codable {
    /// Allow this specific invocation only.
    case allowOnce

    /// Always allow this tool/command pattern for the session.
    case alwaysAllow

    /// Deny this invocation.
    case deny

    /// Deny and block this pattern for the session.
    case denyAndBlock
}

// MARK: - ContextPayload

/// Additional context attached to a RunRequest.
public struct ContextPayload: Sendable, Codable {
    /// Steering messages to inject before this turn.
    public let steering: [String]?

    /// System-level overrides for this turn only.
    public let systemOverrides: [String: String]?

    public init(
        steering: [String]? = nil,
        systemOverrides: [String: String]? = nil
    ) {
        self.steering = steering
        self.systemOverrides = systemOverrides
    }
}

// MARK: - ExecutionPolicy

/// Execution policy for a turn.
public struct ExecutionPolicy: Sendable, Codable {
    /// Maximum duration for the entire turn.
    public let timeout: Duration?

    /// Maximum number of tool calls allowed in a single turn.
    public let maxToolCalls: Int?

    /// Whether to allow interactive approval.
    ///
    /// When `false`, the runtime auto-denies any tool that requires `.ask`
    /// permission. This is useful for headless/batch environments.
    public let allowInteractiveApproval: Bool

    public init(
        timeout: Duration? = nil,
        maxToolCalls: Int? = nil,
        allowInteractiveApproval: Bool = true
    ) {
        self.timeout = timeout
        self.maxToolCalls = maxToolCalls
        self.allowInteractiveApproval = allowInteractiveApproval
    }
}
