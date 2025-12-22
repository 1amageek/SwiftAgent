//
//  PermissionError.swift
//  SwiftAgent
//
//  Created by SwiftAgent on 2025/01/23.
//

import Foundation

/// Errors related to permission checking.
public enum PermissionError: LocalizedError, Sendable {

    /// The tool was denied by a permission rule.
    ///
    /// - Parameters:
    ///   - toolName: The name of the tool.
    ///   - rule: The rule that denied access.
    case deniedByRule(toolName: String, rule: String)

    /// The tool was denied by the permission delegate.
    ///
    /// - Parameters:
    ///   - toolName: The name of the tool.
    ///   - reason: The reason for denial.
    case deniedByDelegate(toolName: String, reason: String?)

    /// The tool was denied by a hook.
    ///
    /// - Parameters:
    ///   - toolName: The name of the tool.
    ///   - reason: The reason for denial.
    case deniedByHook(toolName: String, reason: String?)

    /// The tool was denied due to permission mode restrictions.
    ///
    /// - Parameters:
    ///   - toolName: The name of the tool.
    ///   - mode: The current permission mode.
    case deniedByMode(toolName: String, mode: PermissionMode)

    /// User approval is required for this tool.
    ///
    /// - Parameter toolName: The name of the tool.
    case approvalRequired(toolName: String)

    /// The agent was stopped by a hook or user.
    ///
    /// - Parameter reason: The reason for stopping.
    case agentStopped(reason: String)

    /// Invalid permission rule pattern.
    ///
    /// - Parameter pattern: The invalid pattern.
    case invalidRulePattern(pattern: String)

    /// Permission configuration error.
    ///
    /// - Parameter message: Description of the error.
    case configurationError(message: String)

    public var errorDescription: String? {
        switch self {
        case .deniedByRule(let toolName, let rule):
            return "Tool '\(toolName)' denied by rule: \(rule)"

        case .deniedByDelegate(let toolName, let reason):
            let reasonText = reason.map { ": \($0)" } ?? ""
            return "Tool '\(toolName)' denied by permission delegate\(reasonText)"

        case .deniedByHook(let toolName, let reason):
            let reasonText = reason.map { ": \($0)" } ?? ""
            return "Tool '\(toolName)' denied by hook\(reasonText)"

        case .deniedByMode(let toolName, let mode):
            return "Tool '\(toolName)' denied: not allowed in \(mode.rawValue) mode"

        case .approvalRequired(let toolName):
            return "User approval required for tool '\(toolName)'"

        case .agentStopped(let reason):
            return "Agent stopped: \(reason)"

        case .invalidRulePattern(let pattern):
            return "Invalid permission rule pattern: '\(pattern)'"

        case .configurationError(let message):
            return "Permission configuration error: \(message)"
        }
    }

    /// Whether this error should be shown to the user.
    public var isUserFacing: Bool {
        switch self {
        case .approvalRequired, .agentStopped:
            return true
        default:
            return false
        }
    }

    /// Whether this error can be recovered from.
    public var isRecoverable: Bool {
        switch self {
        case .approvalRequired:
            return true // Can retry with approval
        case .agentStopped:
            return false
        case .deniedByRule, .deniedByDelegate, .deniedByHook, .deniedByMode:
            return false
        case .invalidRulePattern, .configurationError:
            return false
        }
    }
}
