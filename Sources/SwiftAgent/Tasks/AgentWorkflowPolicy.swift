//
//  AgentWorkflowPolicy.swift
//  SwiftAgent
//

import Foundation

/// Execution policy for a workflow graph.
public struct AgentWorkflowPolicy: Sendable, Codable {
    /// Maximum number of steps allowed in the plan.
    public let maxSteps: Int?

    /// Whether execution should stop after the first failed step.
    public let failFast: Bool

    /// Optional wall-clock deadline for starting the workflow.
    public let deadline: Date?

    public init(
        maxSteps: Int? = nil,
        failFast: Bool = true,
        deadline: Date? = nil
    ) {
        self.maxSteps = maxSteps
        self.failFast = failFast
        self.deadline = deadline
    }
}
