//
//  AgentTaskResult.swift
//  SwiftAgent
//

import Foundation

/// Terminal result for an `AgentTaskEnvelope`.
public struct AgentTaskResult: Sendable, Codable {
    public let taskID: String
    public let correlationID: String
    public let sessionID: String
    public let turnID: String
    public let status: RunStatus
    public let finalOutput: String?
    public let usage: TokenUsage?
    public let toolTrace: [ToolTrace]
    public let error: RunEvent.RunError?
    public let duration: Duration

    public init(
        taskID: String,
        correlationID: String,
        sessionID: String,
        turnID: String,
        status: RunStatus,
        finalOutput: String? = nil,
        usage: TokenUsage? = nil,
        toolTrace: [ToolTrace] = [],
        error: RunEvent.RunError? = nil,
        duration: Duration
    ) {
        self.taskID = taskID
        self.correlationID = correlationID
        self.sessionID = sessionID
        self.turnID = turnID
        self.status = status
        self.finalOutput = finalOutput
        self.usage = usage
        self.toolTrace = toolTrace
        self.error = error
        self.duration = duration
    }

    public init(envelope: AgentTaskEnvelope, runResult: RunResult) {
        self.init(
            taskID: envelope.id,
            correlationID: envelope.correlationID,
            sessionID: runResult.sessionID,
            turnID: runResult.turnID,
            status: runResult.status,
            finalOutput: runResult.finalOutput,
            usage: runResult.usage,
            toolTrace: runResult.toolTrace,
            error: runResult.error,
            duration: runResult.duration
        )
    }
}
