//
//  AgentTaskEvent.swift
//  SwiftAgent
//

import Foundation

/// Event stream emitted by `AgentSessionRunner`.
public enum AgentTaskEvent: Sendable, Codable {
    case taskStarted(AgentTaskStarted)
    case runEvent(AgentTaskRunEvent)
    case taskCompleted(AgentTaskCompleted)
}
