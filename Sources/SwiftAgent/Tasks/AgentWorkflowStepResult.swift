//
//  AgentWorkflowStepResult.swift
//  SwiftAgent
//

import Foundation

/// Result captured for one workflow step.
public struct AgentWorkflowStepResult: Sendable, Codable {
    public let stepID: String
    public let assignee: AgentAssignee
    public let taskResult: AgentTaskResult?
    public let error: AgentWorkflowStepError?
    public let startedAt: Date
    public let completedAt: Date
    public let duration: Duration

    public var status: RunStatus {
        taskResult?.status ?? .failed
    }

    public var finalOutput: String? {
        taskResult?.finalOutput
    }

    public init(
        stepID: String,
        assignee: AgentAssignee,
        taskResult: AgentTaskResult?,
        error: AgentWorkflowStepError? = nil,
        startedAt: Date,
        completedAt: Date = Date(),
        duration: Duration
    ) {
        self.stepID = stepID
        self.assignee = assignee
        self.taskResult = taskResult
        self.error = error
        self.startedAt = startedAt
        self.completedAt = completedAt
        self.duration = duration
    }
}
