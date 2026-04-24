//
//  AgentWorkflowStepRole.swift
//  SwiftAgent
//

import Foundation

/// Semantic role of a workflow step.
public enum AgentWorkflowStepRole: String, Sendable, Codable {
    case plan
    case execute
    case verify
    case refine
    case synthesize
}
