//
//  AgentError.swift
//  SwiftAgent
//
//  Created by SwiftAgent on 2025/01/15.
//

import Foundation

/// Errors that can occur during agent operations.
///
/// `AgentError` provides comprehensive error handling for all agent-related operations,
/// including session management and tool execution.
public enum AgentError: Error, LocalizedError, Sendable {

    // MARK: - Session Errors

    /// The requested session was not found.
    case sessionNotFound(id: String)

    /// Failed to save the session.
    case sessionSaveFailed(underlyingError: Error)

    /// Failed to load the session.
    case sessionLoadFailed(id: String, underlyingError: Error)

    /// Session is already responding to a prompt.
    case sessionBusy

    // MARK: - Tool Errors

    /// The requested tool was not found.
    case toolNotFound(name: String)

    /// Tool execution failed.
    case toolExecutionFailed(name: String, underlyingError: Error)

    /// Tool configuration is invalid.
    case invalidToolConfiguration(reason: String)

    // MARK: - Model Errors

    /// Failed to load the model.
    case modelLoadFailed(underlyingError: Error)

    /// Model is not available.
    case modelUnavailable(reason: String)

    // MARK: - Configuration Errors

    /// Configuration is invalid.
    case invalidConfiguration(reason: String)

    // MARK: - Generation Errors

    /// Generation failed.
    case generationFailed(reason: String)

    /// Response decoding failed.
    case decodingFailed(reason: String)

    /// Operation was cancelled.
    case cancelled

    /// Operation timed out.
    case timeout(duration: Duration)

    // MARK: - LocalizedError

    public var errorDescription: String? {
        switch self {
        case .sessionNotFound(let id):
            return "Session not found: '\(id)'"
        case .sessionSaveFailed(let error):
            return "Failed to save session: \(error.localizedDescription)"
        case .sessionLoadFailed(let id, let error):
            return "Failed to load session '\(id)': \(error.localizedDescription)"
        case .sessionBusy:
            return "Session is already responding to a prompt"
        case .toolNotFound(let name):
            return "Tool not found: '\(name)'"
        case .toolExecutionFailed(let name, let error):
            return "Tool '\(name)' execution failed: \(error.localizedDescription)"
        case .invalidToolConfiguration(let reason):
            return "Invalid tool configuration: \(reason)"
        case .modelLoadFailed(let error):
            return "Failed to load model: \(error.localizedDescription)"
        case .modelUnavailable(let reason):
            return "Model unavailable: \(reason)"
        case .invalidConfiguration(let reason):
            return "Invalid configuration: \(reason)"
        case .generationFailed(let reason):
            return "Generation failed: \(reason)"
        case .decodingFailed(let reason):
            return "Decoding failed: \(reason)"
        case .cancelled:
            return "Operation was cancelled"
        case .timeout(let duration):
            return "Operation timed out after \(duration)"
        }
    }

    public var recoverySuggestion: String? {
        switch self {
        case .sessionNotFound:
            return "Create a new session or check the session ID."
        case .sessionSaveFailed:
            return "Check storage permissions and available disk space."
        case .sessionLoadFailed:
            return "The session data may be corrupted. Try creating a new session."
        case .sessionBusy:
            return "Wait for the current operation to complete before sending another prompt."
        case .toolNotFound:
            return "Ensure the tool is included in the ToolConfiguration."
        case .toolExecutionFailed:
            return "Check the tool arguments and implementation."
        case .invalidToolConfiguration:
            return "Review the tool configuration settings."
        case .modelLoadFailed:
            return "Ensure the model is downloaded and accessible."
        case .modelUnavailable:
            return "Check model availability and try again."
        case .invalidConfiguration:
            return "Review the AgentConfiguration settings."
        case .generationFailed:
            return "Modify your prompt or check model constraints."
        case .decodingFailed:
            return "Ensure the response format matches the expected type."
        case .cancelled:
            return "Retry the operation if needed."
        case .timeout:
            return "Consider increasing the timeout or simplifying the request."
        }
    }

    public var failureReason: String? {
        return errorDescription
    }
}

// MARK: - Error Context

extension AgentError {

    /// Additional context for error diagnosis.
    public struct Context: Sendable {
        public let file: String
        public let function: String
        public let line: Int
        public let additionalInfo: [String: String]

        public init(
            file: String = #file,
            function: String = #function,
            line: Int = #line,
            additionalInfo: [String: String] = [:]
        ) {
            self.file = file
            self.function = function
            self.line = line
            self.additionalInfo = additionalInfo
        }
    }
}
