//
//  AgentWorkflowStep.swift
//  SwiftAgent
//

import Foundation

/// One executable step in an agent workflow.
public struct AgentWorkflowStep: Identifiable, Sendable, Codable {
    public let id: String
    public let assignee: AgentAssignee
    public let envelope: AgentTaskEnvelope
    public let access: AgentWorkflowAccess
    public let role: AgentWorkflowStepRole

    public init(
        id: String = UUID().uuidString,
        assignee: AgentAssignee = .localSession,
        envelope: AgentTaskEnvelope,
        access: AgentWorkflowAccess = .none,
        role: AgentWorkflowStepRole = .execute
    ) {
        self.id = id
        self.assignee = assignee
        self.envelope = envelope
        self.access = access
        self.role = role
    }
}
