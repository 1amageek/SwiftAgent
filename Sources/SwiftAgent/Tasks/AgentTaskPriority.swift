//
//  AgentTaskPriority.swift
//  SwiftAgent
//

import Foundation

/// Scheduling priority requested by an agent task.
public enum AgentTaskPriority: Int, Sendable, Codable, Comparable {
    case low = 0
    case normal = 1
    case high = 2
    case urgent = 3

    public static func < (lhs: AgentTaskPriority, rhs: AgentTaskPriority) -> Bool {
        lhs.rawValue < rhs.rawValue
    }
}
