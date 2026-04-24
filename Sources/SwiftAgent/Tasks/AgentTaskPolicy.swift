//
//  AgentTaskPolicy.swift
//  SwiftAgent
//

import Foundation

/// Request-level policy for an agent task.
///
/// Policies carried by an envelope are requests. Runners and coordinators must
/// clamp them against local runtime policy before execution.
public struct AgentTaskPolicy: Sendable, Codable {
    /// Turn execution controls used by the local runner.
    public let execution: ExecutionPolicy

    /// Requested scheduling priority.
    public let priority: AgentTaskPriority

    /// Optional wall-clock deadline for task admission.
    public let deadline: Date?

    /// Maximum number of subtasks this task may create.
    public let maxSubtasks: Int?

    /// Maximum delegation depth requested by the task.
    public let maxDepth: Int?

    /// Capability names required from an assignee.
    public let requiredCapabilities: [String]

    /// Perception names required from an assignee.
    public let requiredPerceptions: [String]

    /// Requested tool visibility for this task.
    public let toolScope: AgentToolScope

    public init(
        execution: ExecutionPolicy = ExecutionPolicy(),
        priority: AgentTaskPriority = .normal,
        deadline: Date? = nil,
        maxSubtasks: Int? = nil,
        maxDepth: Int? = nil,
        requiredCapabilities: [String] = [],
        requiredPerceptions: [String] = [],
        toolScope: AgentToolScope = .all
    ) {
        self.execution = execution
        self.priority = priority
        self.deadline = deadline
        self.maxSubtasks = maxSubtasks
        self.maxDepth = maxDepth
        self.requiredCapabilities = requiredCapabilities
        self.requiredPerceptions = requiredPerceptions
        self.toolScope = toolScope
    }
}
