//
//  ToolExecutionError.swift
//  SwiftAgent
//
//  Created by SwiftAgent on 2025/01/15.
//

import Foundation

/// Errors that can occur during tool execution in the pipeline.
public enum ToolExecutionError: Error, LocalizedError {

    /// Permission was denied for the tool.
    ///
    /// - Parameters:
    ///   - toolName: The name of the tool.
    ///   - reason: The reason for denial.
    case permissionDenied(toolName: String, reason: String?)

    /// Execution was interrupted by a permission check.
    ///
    /// - Parameters:
    ///   - toolName: The name of the tool.
    ///   - reason: The reason for interruption.
    case executionInterrupted(toolName: String, reason: String?)

    /// Execution was blocked by a hook.
    ///
    /// - Parameters:
    ///   - toolName: The name of the tool.
    ///   - reason: The reason for blocking.
    case blockedByHook(toolName: String, reason: String?)

    /// User approval is required before execution.
    ///
    /// - Parameter toolName: The name of the tool.
    case approvalRequired(toolName: String)

    /// Tool execution timed out.
    ///
    /// - Parameter duration: The timeout duration that was exceeded.
    case timeout(duration: Duration)

    /// All retry attempts were exhausted.
    ///
    /// - Parameters:
    ///   - attempts: The number of attempts made.
    ///   - lastError: The last error encountered.
    case retryExhausted(attempts: Int, lastError: Error)

    /// Tool was not found.
    ///
    /// - Parameter toolName: The name of the tool.
    case toolNotFound(toolName: String)

    /// Invalid arguments were provided.
    ///
    /// - Parameters:
    ///   - toolName: The name of the tool.
    ///   - reason: The reason the arguments are invalid.
    case invalidArguments(toolName: String, reason: String)

    /// A fallback output was requested by an error hook.
    ///
    /// This error is thrown by the pipeline when a hook returns `.fallback(output:)`.
    /// It should be caught by `PipelineWrappedTool` which can return the string output directly.
    ///
    /// - Parameter output: The fallback output string to return.
    case fallbackRequested(output: String)

    /// Failed to parse modified arguments.
    ///
    /// This error occurs when a permission delegate or hook modifies the arguments JSON,
    /// but the modified JSON cannot be parsed back into the tool's Arguments type.
    ///
    /// - Parameters:
    ///   - toolName: The name of the tool.
    ///   - json: The modified JSON that failed to parse.
    ///   - underlyingError: The error that occurred during parsing.
    case argumentParseFailed(toolName: String, json: String, underlyingError: Error)

    /// An unknown error occurred.
    case unknown

    public var errorDescription: String? {
        switch self {
        case .permissionDenied(let name, let reason):
            let reasonText = reason ?? "No reason provided"
            return "Permission denied for '\(name)': \(reasonText)"

        case .executionInterrupted(let name, let reason):
            let reasonText = reason ?? "No reason provided"
            return "Execution interrupted for '\(name)': \(reasonText)"

        case .blockedByHook(let name, let reason):
            let reasonText = reason ?? "No reason provided"
            return "Execution blocked by hook for '\(name)': \(reasonText)"

        case .approvalRequired(let name):
            return "User approval required for '\(name)'"

        case .timeout(let duration):
            return "Tool execution timed out after \(duration)"

        case .retryExhausted(let attempts, let lastError):
            return "Retry exhausted after \(attempts) attempts. Last error: \(lastError.localizedDescription)"

        case .toolNotFound(let name):
            return "Tool not found: '\(name)'"

        case .invalidArguments(let name, let reason):
            return "Invalid arguments for '\(name)': \(reason)"

        case .fallbackRequested(let output):
            return "Fallback requested with output: \(output.prefix(100))..."

        case .argumentParseFailed(let name, _, let underlyingError):
            return "Failed to parse modified arguments for '\(name)': \(underlyingError.localizedDescription)"

        case .unknown:
            return "Unknown tool execution error"
        }
    }

    /// A short code for the error type.
    public var errorCodeString: String {
        switch self {
        case .permissionDenied:
            return "PERMISSION_DENIED"
        case .executionInterrupted:
            return "EXECUTION_INTERRUPTED"
        case .blockedByHook:
            return "BLOCKED_BY_HOOK"
        case .approvalRequired:
            return "APPROVAL_REQUIRED"
        case .timeout:
            return "TIMEOUT"
        case .retryExhausted:
            return "RETRY_EXHAUSTED"
        case .toolNotFound:
            return "TOOL_NOT_FOUND"
        case .invalidArguments:
            return "INVALID_ARGUMENTS"
        case .fallbackRequested:
            return "FALLBACK_REQUESTED"
        case .argumentParseFailed:
            return "ARGUMENT_PARSE_FAILED"
        case .unknown:
            return "UNKNOWN"
        }
    }

    /// Whether this error is recoverable.
    ///
    /// Recoverable errors might succeed if retried.
    public var isRecoverable: Bool {
        switch self {
        case .timeout, .retryExhausted:
            return true
        default:
            return false
        }
    }

    /// Whether this error is a permission issue.
    public var isPermissionError: Bool {
        switch self {
        case .permissionDenied, .approvalRequired, .blockedByHook:
            return true
        default:
            return false
        }
    }
}

// MARK: - Equatable

extension ToolExecutionError: Equatable {
    public static func == (lhs: ToolExecutionError, rhs: ToolExecutionError) -> Bool {
        switch (lhs, rhs) {
        case (.permissionDenied(let n1, let r1), .permissionDenied(let n2, let r2)):
            return n1 == n2 && r1 == r2
        case (.executionInterrupted(let n1, let r1), .executionInterrupted(let n2, let r2)):
            return n1 == n2 && r1 == r2
        case (.blockedByHook(let n1, let r1), .blockedByHook(let n2, let r2)):
            return n1 == n2 && r1 == r2
        case (.approvalRequired(let n1), .approvalRequired(let n2)):
            return n1 == n2
        case (.timeout(let d1), .timeout(let d2)):
            return d1 == d2
        case (.toolNotFound(let n1), .toolNotFound(let n2)):
            return n1 == n2
        case (.invalidArguments(let n1, let r1), .invalidArguments(let n2, let r2)):
            return n1 == n2 && r1 == r2
        case (.unknown, .unknown):
            return true
        case (.retryExhausted(let a1, _), .retryExhausted(let a2, _)):
            // Can't compare errors directly, so just compare attempts
            return a1 == a2
        case (.fallbackRequested(let o1), .fallbackRequested(let o2)):
            return o1 == o2
        case (.argumentParseFailed(let n1, let j1, _), .argumentParseFailed(let n2, let j2, _)):
            // Can't compare errors directly, so just compare name and json
            return n1 == n2 && j1 == j2
        default:
            return false
        }
    }
}

// MARK: - CustomNSError

extension ToolExecutionError: CustomNSError {
    public static var errorDomain: String {
        "SwiftAgent.ToolExecutionError"
    }

    public var errorCode: Int {
        switch self {
        case .permissionDenied: return 1
        case .executionInterrupted: return 2
        case .blockedByHook: return 3
        case .approvalRequired: return 4
        case .timeout: return 5
        case .retryExhausted: return 6
        case .toolNotFound: return 7
        case .invalidArguments: return 8
        case .fallbackRequested: return 9
        case .argumentParseFailed: return 10
        case .unknown: return 99
        }
    }

    public var errorUserInfo: [String: Any] {
        var info: [String: Any] = [
            NSLocalizedDescriptionKey: errorDescription ?? "Unknown error"
        ]

        switch self {
        case .permissionDenied(let name, _),
             .executionInterrupted(let name, _),
             .blockedByHook(let name, _),
             .approvalRequired(let name),
             .toolNotFound(let name),
             .invalidArguments(let name, _):
            info["toolName"] = name

        case .timeout(let duration):
            info["timeout"] = duration

        case .retryExhausted(let attempts, let lastError):
            info["attempts"] = attempts
            info["lastError"] = lastError

        case .fallbackRequested(let output):
            info["fallbackOutput"] = output

        case .argumentParseFailed(let name, let json, let underlyingError):
            info["toolName"] = name
            info["json"] = json
            info["underlyingError"] = underlyingError

        case .unknown:
            break
        }

        return info
    }
}
