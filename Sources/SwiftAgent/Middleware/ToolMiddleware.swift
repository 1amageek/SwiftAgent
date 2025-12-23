//
//  ToolMiddleware.swift
//  SwiftAgent
//
//  Created by SwiftAgent on 2025/01/23.
//

import Foundation

/// Context passed through the middleware chain.
public struct ToolContext: Sendable {
    /// The name of the tool being called.
    public let toolName: String

    /// The tool arguments as JSON string.
    public let arguments: String

    /// The tool use ID (if available).
    public let toolUseID: String?

    /// The session ID (if available).
    public let sessionID: String?

    /// Additional metadata.
    public var metadata: [String: String]

    public init(
        toolName: String,
        arguments: String,
        toolUseID: String? = nil,
        sessionID: String? = nil,
        metadata: [String: String] = [:]
    ) {
        self.toolName = toolName
        self.arguments = arguments
        self.toolUseID = toolUseID
        self.sessionID = sessionID
        self.metadata = metadata
    }
}

/// Result of tool execution passed back through the middleware chain.
public struct ToolResult: Sendable {
    /// The tool output.
    public let output: String

    /// Execution duration.
    public let duration: Duration

    /// Whether the tool succeeded.
    public let success: Bool

    /// Error if failed.
    public let error: Error?

    public init(
        output: String,
        duration: Duration,
        success: Bool = true,
        error: Error? = nil
    ) {
        self.output = output
        self.duration = duration
        self.success = success
        self.error = error
    }

    /// Creates a successful result.
    public static func success(_ output: String, duration: Duration) -> ToolResult {
        ToolResult(output: output, duration: duration, success: true)
    }

    /// Creates a failed result.
    public static func failure(_ error: Error, duration: Duration) -> ToolResult {
        ToolResult(
            output: error.localizedDescription,
            duration: duration,
            success: false,
            error: error
        )
    }
}

/// A middleware that can intercept tool execution.
///
/// Middleware follows the chain-of-responsibility pattern.
/// Each middleware can:
/// - Modify the context before passing to the next middleware
/// - Short-circuit the chain by not calling `next`
/// - Modify the result before returning
///
/// ## Example
///
/// ```swift
/// struct LoggingMiddleware: ToolMiddleware {
///     func handle(
///         _ context: ToolContext,
///         next: @escaping Next
///     ) async throws -> ToolResult {
///         print("Calling: \(context.toolName)")
///         let result = try await next(context)
///         print("Result: \(result.output)")
///         return result
///     }
/// }
/// ```
public protocol ToolMiddleware: Sendable {
    /// The type for the next handler in the chain.
    typealias Next = @Sendable (ToolContext) async throws -> ToolResult

    /// Handles the tool execution.
    ///
    /// - Parameters:
    ///   - context: The tool context.
    ///   - next: The next handler in the chain.
    /// - Returns: The tool result.
    func handle(_ context: ToolContext, next: @escaping Next) async throws -> ToolResult
}
