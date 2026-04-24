//
//  AgentTaskRunEvent.swift
//  SwiftAgent
//

import Foundation

/// A `RunEvent` annotated with task identity.
public struct AgentTaskRunEvent: Sendable, Codable {
    public let taskID: String
    public let correlationID: String
    public let event: RunEvent

    public init(taskID: String, correlationID: String, event: RunEvent) {
        self.taskID = taskID
        self.correlationID = correlationID
        self.event = event
    }
}
