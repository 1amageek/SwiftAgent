//
//  AgentTaskCompleted.swift
//  SwiftAgent
//

import Foundation

/// Task lifecycle event emitted when a runner reaches a terminal result.
public struct AgentTaskCompleted: Sendable, Codable {
    public let result: AgentTaskResult
    public let timestamp: Date

    public init(result: AgentTaskResult, timestamp: Date = Date()) {
        self.result = result
        self.timestamp = timestamp
    }
}
