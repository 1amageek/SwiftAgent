//
//  AgentWorkflowStatus.swift
//  SwiftAgent
//

import Foundation

/// Terminal status for a workflow execution.
public enum AgentWorkflowStatus: String, Sendable, Codable {
    case completed
    case partiallyCompleted
    case failed
    case cancelled
    case timedOut
}
