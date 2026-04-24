//
//  AgentWorkflowPlan.swift
//  SwiftAgent
//

import Foundation

/// A typed task graph plus context routing rules.
public struct AgentWorkflowPlan: Identifiable, Sendable, Codable {
    public let id: String
    public let correlationID: String
    public let rootTaskID: String?
    public let steps: [AgentWorkflowStep]
    public let finalStepID: String?
    public let policy: AgentWorkflowPolicy
    public let metadata: [String: String]

    public init(
        id: String = UUID().uuidString,
        correlationID: String = UUID().uuidString,
        rootTaskID: String? = nil,
        steps: [AgentWorkflowStep],
        finalStepID: String? = nil,
        policy: AgentWorkflowPolicy = AgentWorkflowPolicy(),
        metadata: [String: String] = [:]
    ) {
        self.id = id
        self.correlationID = correlationID
        self.rootTaskID = rootTaskID
        self.steps = steps
        self.finalStepID = finalStepID
        self.policy = policy
        self.metadata = metadata
    }
}
