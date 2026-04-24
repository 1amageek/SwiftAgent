//
//  AgentSessionRunnerError.swift
//  SwiftAgent
//

import Foundation

/// Errors raised by `AgentSessionRunner` before task execution.
public enum AgentSessionRunnerError: Error, LocalizedError, Sendable {
    case deadlineExceeded(Date)

    public var errorDescription: String? {
        switch self {
        case .deadlineExceeded(let deadline):
            "Agent task deadline has already passed: \(deadline)"
        }
    }
}
