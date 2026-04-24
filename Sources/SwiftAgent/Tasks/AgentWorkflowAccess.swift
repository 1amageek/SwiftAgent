//
//  AgentWorkflowAccess.swift
//  SwiftAgent
//

import Foundation

/// Context access granted to a workflow step.
public enum AgentWorkflowAccess: Sendable, Codable {
    /// The step receives no previous workflow results.
    case none

    /// The step receives all previous workflow results.
    case allPrevious

    /// The step receives only the listed previous workflow results.
    case steps([String])
}
