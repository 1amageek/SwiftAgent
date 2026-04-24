//
//  AgentTaskRelation.swift
//  SwiftAgent
//

import Foundation

/// Trace relationship between tasks.
///
/// Relations describe provenance and correlation. They do not grant control
/// over another agent or session.
public enum AgentTaskRelation: Sendable, Codable {
    /// A root task initiated by a user or host application.
    case root

    /// A task delegated from another task.
    case delegated(parentTaskID: String?)

    /// A task requested by a peer agent.
    case peerRequest

    /// A task resumed from a previous task.
    case resumed(previousTaskID: String)
}
