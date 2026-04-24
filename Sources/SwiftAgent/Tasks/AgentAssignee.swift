//
//  AgentAssignee.swift
//  SwiftAgent
//

import Foundation

/// A requested executor for a workflow step.
///
/// Assignees are routing requests. The workflow executor resolves them against
/// local policy and available runners.
public enum AgentAssignee: Sendable, Codable {
    /// Execute in the local process using the configured session runner.
    case localSession

    /// Execute on a specific community member.
    case member(id: String)

    /// Execute on any agent that provides the requested capability.
    case capability(String)

    /// Execute through the configured planner session.
    case planner
}
