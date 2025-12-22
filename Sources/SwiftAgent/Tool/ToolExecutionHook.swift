//
//  ToolExecutionHook.swift
//  SwiftAgent
//
//  Created by SwiftAgent on 2025/01/15.
//

import Foundation

/// A protocol for intercepting tool execution lifecycle events.
///
/// Implement this protocol to add custom behavior before or after tool execution,
/// or to handle errors in a custom way.
///
/// ## Usage
///
/// ```swift
/// struct LoggingHook: ToolExecutionHook {
///     func beforeExecution(
///         toolName: String,
///         arguments: String,
///         context: ToolExecutionContext
///     ) async throws -> ToolHookDecision {
///         print("Executing \(toolName)...")
///         return .proceed
///     }
///
///     func afterExecution(
///         toolName: String,
///         arguments: String,
///         output: String,
///         duration: Duration,
///         context: ToolExecutionContext
///     ) async throws {
///         print("Completed \(toolName) in \(duration)")
///     }
/// }
/// ```
public protocol ToolExecutionHook: Sendable {

    /// Called before a tool is executed.
    ///
    /// - Parameters:
    ///   - toolName: The name of the tool being executed.
    ///   - arguments: The JSON-encoded arguments for the tool.
    ///   - context: Execution context with session and trace information.
    /// - Returns: A decision on whether to proceed with execution.
    func beforeExecution(
        toolName: String,
        arguments: String,
        context: ToolExecutionContext
    ) async throws -> ToolHookDecision

    /// Called after a tool executes successfully.
    ///
    /// - Parameters:
    ///   - toolName: The name of the tool that was executed.
    ///   - arguments: The JSON-encoded arguments that were used.
    ///   - output: The string output from the tool.
    ///   - duration: How long the execution took.
    ///   - context: Execution context with session and trace information.
    func afterExecution(
        toolName: String,
        arguments: String,
        output: String,
        duration: Duration,
        context: ToolExecutionContext
    ) async throws

    /// Called when a tool execution fails.
    ///
    /// - Parameters:
    ///   - toolName: The name of the tool that failed.
    ///   - arguments: The JSON-encoded arguments that were used.
    ///   - error: The error that occurred.
    ///   - context: Execution context with session and trace information.
    /// - Returns: A recovery strategy for the error.
    func onError(
        toolName: String,
        arguments: String,
        error: Error,
        context: ToolExecutionContext
    ) async throws -> ToolErrorRecovery
}

// MARK: - Default Implementation

extension ToolExecutionHook {

    public func beforeExecution(
        toolName: String,
        arguments: String,
        context: ToolExecutionContext
    ) async throws -> ToolHookDecision {
        .proceed
    }

    public func afterExecution(
        toolName: String,
        arguments: String,
        output: String,
        duration: Duration,
        context: ToolExecutionContext
    ) async throws {
        // Default: no-op
    }

    public func onError(
        toolName: String,
        arguments: String,
        error: Error,
        context: ToolExecutionContext
    ) async throws -> ToolErrorRecovery {
        .rethrow
    }
}

// MARK: - ToolHookDecision

/// The decision returned by a hook's `beforeExecution` method.
public enum ToolHookDecision: Sendable {
    /// Proceed with the tool execution as normal.
    case proceed

    /// Proceed with modified arguments.
    ///
    /// The pipeline will deserialize the modified JSON back into the tool's
    /// `Arguments` type using `GeneratedContent(json:)` and `T.Arguments(content)`.
    ///
    /// - Parameter arguments: The modified JSON-encoded arguments.
    ///
    /// ## Example
    ///
    /// ```swift
    /// func beforeExecution(
    ///     toolName: String,
    ///     arguments: String,
    ///     context: ToolExecutionContext
    /// ) async throws -> ToolHookDecision {
    ///     // Sanitize paths by replacing dangerous directories
    ///     if arguments.contains("/etc/") {
    ///         let sanitized = arguments.replacingOccurrences(of: "/etc/", with: "/tmp/")
    ///         return .proceedWithModifiedArgs(sanitized)
    ///     }
    ///     return .proceed
    /// }
    /// ```
    case proceedWithModifiedArgs(String)

    /// Block the tool execution entirely.
    ///
    /// - Parameter reason: Optional reason for blocking.
    case block(reason: String?)

    /// Require user approval before proceeding.
    ///
    /// This throws `ToolExecutionError.approvalRequired` to signal that
    /// the caller should request user confirmation and retry.
    case requireApproval
}

// MARK: - ToolErrorRecovery

/// Strategy for recovering from a tool execution error.
public enum ToolErrorRecovery: Sendable {
    /// Re-throw the error as-is.
    case rethrow

    /// Retry the operation after a delay.
    ///
    /// - Parameter delay: How long to wait before retrying.
    case retry(after: Duration)

    /// Return a fallback output instead of failing.
    ///
    /// The pipeline throws a special `ToolExecutionError.fallbackRequested` error,
    /// which is caught by `PipelineWrappedTool`. Since the wrapper's output is `String`,
    /// it can safely return the fallback string directly to the caller.
    ///
    /// - Parameter output: The fallback output string to return.
    ///
    /// ## Example
    ///
    /// ```swift
    /// func onError(
    ///     toolName: String,
    ///     arguments: String,
    ///     error: Error,
    ///     context: ToolExecutionContext
    /// ) async throws -> ToolErrorRecovery {
    ///     if error is URLError {
    ///         return .fallback(output: "Network unavailable. Using cached response.")
    ///     }
    ///     return .rethrow
    /// }
    /// ```
    case fallback(output: String)
}

// MARK: - Convenience Hooks

/// A simple logging hook that prints tool execution events.
public struct LoggingToolHook: ToolExecutionHook {

    private let logger: @Sendable (String) -> Void

    /// Creates a logging hook.
    ///
    /// - Parameter logger: A function to call with log messages. Defaults to `print`.
    public init(logger: @escaping @Sendable (String) -> Void = { print($0) }) {
        self.logger = logger
    }

    public func beforeExecution(
        toolName: String,
        arguments: String,
        context: ToolExecutionContext
    ) async throws -> ToolHookDecision {
        let traceID = context.traceID ?? "?"
        logger("[\(traceID)] Executing \(toolName)")
        return .proceed
    }

    public func afterExecution(
        toolName: String,
        arguments: String,
        output: String,
        duration: Duration,
        context: ToolExecutionContext
    ) async throws {
        let traceID = context.traceID ?? "?"
        logger("[\(traceID)] Completed \(toolName) in \(duration)")
    }

    public func onError(
        toolName: String,
        arguments: String,
        error: Error,
        context: ToolExecutionContext
    ) async throws -> ToolErrorRecovery {
        let traceID = context.traceID ?? "?"
        logger("[\(traceID)] Error in \(toolName): \(error)")
        return .rethrow
    }
}

/// A hook that blocks specific tools.
public struct ToolBlockingHook: ToolExecutionHook {

    private let blockedTools: Set<String>
    private let reason: String?

    /// Creates a hook that blocks specific tools.
    ///
    /// - Parameters:
    ///   - tools: Names of tools to block.
    ///   - reason: Optional reason for blocking.
    public init(blocking tools: Set<String>, reason: String? = nil) {
        self.blockedTools = tools
        self.reason = reason
    }

    public func beforeExecution(
        toolName: String,
        arguments: String,
        context: ToolExecutionContext
    ) async throws -> ToolHookDecision {
        if blockedTools.contains(toolName) {
            return .block(reason: reason ?? "Tool '\(toolName)' is blocked")
        }
        return .proceed
    }
}
