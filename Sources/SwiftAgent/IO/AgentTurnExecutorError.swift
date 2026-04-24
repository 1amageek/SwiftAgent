//
//  AgentTurnExecutorError.swift
//  SwiftAgent
//

import Foundation

enum AgentTurnExecutorError: Error, LocalizedError, Sendable {
    case unsupportedInput(String)
    case timedOut(Duration)

    var errorDescription: String? {
        switch self {
        case .unsupportedInput(let input):
            "AgentTurnExecutor cannot execute input payload: \(input)"
        case .timedOut(let timeout):
            "Agent turn timed out after \(timeout)"
        }
    }
}
