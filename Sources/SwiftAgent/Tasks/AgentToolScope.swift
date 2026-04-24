//
//  AgentToolScope.swift
//  SwiftAgent
//

import Foundation

/// The set of tools requested by an agent task.
///
/// This is a request-level constraint, not a source of authority. The local
/// runtime still decides which tools are actually registered and allowed.
public enum AgentToolScope: Sendable, Codable {
    /// No tools are requested.
    case none

    /// All locally configured tools may be considered by the runner.
    case all

    /// Only tools with these names are requested.
    case listed([String])
}
