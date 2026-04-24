//
//  AgentTaskStarted.swift
//  SwiftAgent
//

import Foundation

/// Task lifecycle event emitted when a runner starts a task.
public struct AgentTaskStarted: Sendable, Codable {
    public let taskID: String
    public let correlationID: String
    public let sessionID: String
    public let turnID: String
    public let timestamp: Date

    public init(
        taskID: String,
        correlationID: String,
        sessionID: String,
        turnID: String,
        timestamp: Date = Date()
    ) {
        self.taskID = taskID
        self.correlationID = correlationID
        self.sessionID = sessionID
        self.turnID = turnID
        self.timestamp = timestamp
    }
}
