//
//  AgentWorkflowStepError.swift
//  SwiftAgent
//

import Foundation

/// Serializable error captured for a workflow step.
public struct AgentWorkflowStepError: Sendable, Codable {
    public let message: String
    public let code: String?

    public init(message: String, code: String? = nil) {
        self.message = message
        self.code = code
    }
}
