//
//  RunResult.swift
//  SwiftAgent
//

import Foundation

/// The final result of an Agent run (one turn).
///
/// `RunResult` is returned by `Agent.run(_:)` and also emitted as a
/// `.runCompleted` event to the transport. Consumers can either
/// await the return value (programmatic use) or observe the event
/// stream (transport use).
public struct RunResult: Sendable {

    /// The session ID.
    public let sessionID: String

    /// The turn ID.
    public let turnID: String

    /// Terminal status of the run.
    public let status: RunStatus

    /// The final text output (if completed successfully).
    public let finalOutput: String?

    /// Token usage statistics (if available from the LLM provider).
    public let usage: TokenUsage?

    /// Ordered trace of tool invocations during this turn.
    public let toolTrace: [ToolTrace]

    /// Error details (if failed).
    public let error: RunEvent.RunError?

    /// Total wall-clock duration of the run.
    public let duration: Duration

    public init(
        sessionID: String,
        turnID: String,
        status: RunStatus,
        finalOutput: String? = nil,
        usage: TokenUsage? = nil,
        toolTrace: [ToolTrace] = [],
        error: RunEvent.RunError? = nil,
        duration: Duration
    ) {
        self.sessionID = sessionID
        self.turnID = turnID
        self.status = status
        self.finalOutput = finalOutput
        self.usage = usage
        self.toolTrace = toolTrace
        self.error = error
        self.duration = duration
    }
}

// MARK: - RunStatus

/// Terminal status of a run.
public enum RunStatus: String, Sendable, Codable {
    /// The run completed successfully.
    case completed

    /// The run failed with an error.
    case failed

    /// The run was cancelled by the client.
    case cancelled

    /// The run was denied (e.g., all tools blocked by permissions).
    case denied

    /// The run exceeded its timeout.
    case timedOut
}

// MARK: - TokenUsage

/// Token usage statistics.
public struct TokenUsage: Sendable, Codable {
    public let inputTokens: Int
    public let outputTokens: Int

    public var totalTokens: Int { inputTokens + outputTokens }

    public init(inputTokens: Int, outputTokens: Int) {
        self.inputTokens = inputTokens
        self.outputTokens = outputTokens
    }
}

// MARK: - ToolTrace

/// A structured audit record for a single tool invocation.
///
/// Accumulated during a run and included in `RunResult.toolTrace`.
public struct ToolTrace: Sendable, Codable {

    /// Unique identifier for this trace entry.
    public let toolUseID: String

    /// The tool that was called.
    public let toolName: String

    /// SHA-256 digest of the arguments (first 16 hex chars).
    public let argumentsDigest: String

    /// The permission decision that was made.
    public let decision: TraceDecision

    /// Wall-clock duration of the tool execution (nil if denied before execution).
    public let duration: Duration?

    /// Exit code for command-execution tools (Bash), nil for others.
    public let exitCode: Int32?

    /// When the tool call was initiated.
    public let timestamp: Date

    public init(
        toolUseID: String = UUID().uuidString,
        toolName: String,
        argumentsDigest: String,
        decision: TraceDecision,
        duration: Duration? = nil,
        exitCode: Int32? = nil,
        timestamp: Date = Date()
    ) {
        self.toolUseID = toolUseID
        self.toolName = toolName
        self.argumentsDigest = argumentsDigest
        self.decision = decision
        self.duration = duration
        self.exitCode = exitCode
        self.timestamp = timestamp
    }
}

// MARK: - TraceDecision

/// The permission decision recorded in a tool trace.
public enum TraceDecision: String, Sendable, Codable {
    /// Allowed by rule (no user interaction needed).
    case allowed

    /// Denied by a deny rule.
    case denied

    /// Denied by a finalDeny rule (absolute, not overridable).
    case finalDenied

    /// Allowed after user approved.
    case approvedByUser

    /// Denied by user.
    case deniedByUser

    /// Denied because the transport cannot handle interactive approval.
    case transportDenied
}
