//
//  AgentWorkflowExecutorError.swift
//  SwiftAgent
//

import Foundation

/// Errors raised before workflow execution can continue.
public enum AgentWorkflowExecutorError: Error, LocalizedError, Sendable {
    case duplicateStepID(String)
    case unknownAccessStep(stepID: String, referencedStepID: String)
    case forwardAccess(stepID: String, referencedStepID: String)
    case missingExternalHandler(AgentAssignee)
    case stepLimitExceeded(limit: Int, actual: Int)
    case deadlineExceeded(Date)
    case finalStepNotFound(String)
    case contextEncodingFailed

    public var errorDescription: String? {
        switch self {
        case .duplicateStepID(let stepID):
            "Workflow contains duplicate step ID: \(stepID)"
        case .unknownAccessStep(let stepID, let referencedStepID):
            "Workflow step \(stepID) references unknown step \(referencedStepID)"
        case .forwardAccess(let stepID, let referencedStepID):
            "Workflow step \(stepID) cannot access future step \(referencedStepID)"
        case .missingExternalHandler(let assignee):
            "Workflow step requires external assignee handler: \(assignee)"
        case .stepLimitExceeded(let limit, let actual):
            "Workflow step limit exceeded: limit \(limit), actual \(actual)"
        case .deadlineExceeded(let deadline):
            "Workflow deadline has already passed: \(deadline)"
        case .finalStepNotFound(let stepID):
            "Workflow final step not found: \(stepID)"
        case .contextEncodingFailed:
            "Workflow context could not be encoded"
        }
    }
}
