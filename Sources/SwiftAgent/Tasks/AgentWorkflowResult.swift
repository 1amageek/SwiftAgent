//
//  AgentWorkflowResult.swift
//  SwiftAgent
//

import Foundation

/// Terminal result of a workflow execution.
public struct AgentWorkflowResult: Sendable, Codable {
    public let planID: String
    public let correlationID: String
    public let status: AgentWorkflowStatus
    public let stepResults: [AgentWorkflowStepResult]
    public let finalOutput: String?
    public let duration: Duration

    public init(
        planID: String,
        correlationID: String,
        status: AgentWorkflowStatus,
        stepResults: [AgentWorkflowStepResult],
        finalOutput: String?,
        duration: Duration
    ) {
        self.planID = planID
        self.correlationID = correlationID
        self.status = status
        self.stepResults = stepResults
        self.finalOutput = finalOutput
        self.duration = duration
    }
}
