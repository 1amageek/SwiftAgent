//
//  BasicMiddleware.swift
//  SwiftAgent
//
//  Created by SwiftAgent on 2025/01/23.
//

import Foundation

// MARK: - LoggingMiddleware

/// Middleware that logs tool execution.
///
/// ## Example
///
/// ```swift
/// let pipeline = ToolPipeline()
///     .use(LoggingMiddleware { print($0) })
/// ```
public struct LoggingMiddleware: ToolMiddleware {
    public enum LogLevel: Sendable {
        case debug
        case info
        case warning
        case error
    }

    public struct LogEntry: Sendable {
        public let timestamp: Date
        public let level: LogLevel
        public let toolName: String
        public let message: String
        public let duration: Duration?
    }

    private let logger: @Sendable (LogEntry) -> Void

    public init(logger: @escaping @Sendable (LogEntry) -> Void = { entry in
        print("[\(entry.level)] \(entry.toolName): \(entry.message)")
    }) {
        self.logger = logger
    }

    public func handle(_ context: ToolContext, next: @escaping Next) async throws -> ToolResult {
        logger(LogEntry(
            timestamp: Date(),
            level: .info,
            toolName: context.toolName,
            message: "Starting execution",
            duration: nil
        ))

        do {
            let result = try await next(context)

            logger(LogEntry(
                timestamp: Date(),
                level: result.success ? .info : .warning,
                toolName: context.toolName,
                message: result.success ? "Completed" : "Failed: \(result.output)",
                duration: result.duration
            ))

            return result
        } catch {
            logger(LogEntry(
                timestamp: Date(),
                level: .error,
                toolName: context.toolName,
                message: "Error: \(error.localizedDescription)",
                duration: nil
            ))
            throw error
        }
    }
}

// MARK: - PermissionMiddleware

/// Middleware that checks permissions before tool execution.
///
/// ## Example
///
/// ```swift
/// let pipeline = ToolPipeline()
///     .use(PermissionMiddleware { context in
///         // Return true to allow, false to deny
///         return context.toolName != "dangerous_tool"
///     })
/// ```
public struct PermissionMiddleware: ToolMiddleware {
    /// Error thrown when permission is denied.
    public struct PermissionDenied: Error, LocalizedError {
        public let toolName: String
        public let reason: String?

        public var errorDescription: String? {
            if let reason = reason {
                return "Permission denied for '\(toolName)': \(reason)"
            }
            return "Permission denied for '\(toolName)'"
        }
    }

    private let check: @Sendable (ToolContext) async throws -> Bool
    private let onDenied: (@Sendable (ToolContext) -> String?)?

    /// Creates a permission middleware with a check closure.
    ///
    /// - Parameters:
    ///   - check: Returns `true` to allow, `false` to deny.
    ///   - onDenied: Optional closure that returns a denial reason.
    public init(
        check: @escaping @Sendable (ToolContext) async throws -> Bool,
        onDenied: (@Sendable (ToolContext) -> String?)? = nil
    ) {
        self.check = check
        self.onDenied = onDenied
    }

    /// Creates a permission middleware that allows specific tools.
    ///
    /// - Parameter allowedTools: Set of allowed tool names.
    public static func allowList(_ allowedTools: Set<String>) -> PermissionMiddleware {
        PermissionMiddleware(
            check: { allowedTools.contains($0.toolName) },
            onDenied: { _ in "Tool not in allow list" }
        )
    }

    /// Creates a permission middleware that blocks specific tools.
    ///
    /// - Parameter blockedTools: Set of blocked tool names.
    public static func blockList(_ blockedTools: Set<String>) -> PermissionMiddleware {
        PermissionMiddleware(
            check: { !blockedTools.contains($0.toolName) },
            onDenied: { _ in "Tool is blocked" }
        )
    }

    public func handle(_ context: ToolContext, next: @escaping Next) async throws -> ToolResult {
        let allowed = try await check(context)

        guard allowed else {
            let reason = onDenied?(context)
            throw PermissionDenied(toolName: context.toolName, reason: reason)
        }

        return try await next(context)
    }
}

// MARK: - RetryMiddleware

/// Middleware that retries failed tool executions.
///
/// ## Example
///
/// ```swift
/// let pipeline = ToolPipeline()
///     .use(RetryMiddleware(maxAttempts: 3, delay: .seconds(1)))
/// ```
public struct RetryMiddleware: ToolMiddleware {
    private let maxAttempts: Int
    private let delay: Duration
    private let shouldRetry: @Sendable (Error) -> Bool

    /// Creates a retry middleware.
    ///
    /// - Parameters:
    ///   - maxAttempts: Maximum number of attempts (default: 3).
    ///   - delay: Delay between retries (default: 1 second).
    ///   - shouldRetry: Closure to determine if an error should trigger a retry.
    public init(
        maxAttempts: Int = 3,
        delay: Duration = .seconds(1),
        shouldRetry: @escaping @Sendable (Error) -> Bool = { _ in true }
    ) {
        self.maxAttempts = max(1, maxAttempts)
        self.delay = delay
        self.shouldRetry = shouldRetry
    }

    public func handle(_ context: ToolContext, next: @escaping Next) async throws -> ToolResult {
        var lastError: Error?

        for attempt in 1...maxAttempts {
            do {
                let result = try await next(context)

                // If the result indicates failure but didn't throw, check if we should retry
                if !result.success, let error = result.error, shouldRetry(error), attempt < maxAttempts {
                    lastError = error
                    try await Task.sleep(for: delay)
                    continue
                }

                return result
            } catch {
                lastError = error

                if !shouldRetry(error) || attempt == maxAttempts {
                    throw error
                }

                try await Task.sleep(for: delay)
            }
        }

        throw lastError ?? CancellationError()
    }
}

// MARK: - TimeoutMiddleware

/// Middleware that enforces execution timeout.
///
/// ## Example
///
/// ```swift
/// let pipeline = ToolPipeline()
///     .use(TimeoutMiddleware(duration: .seconds(30)))
/// ```
public struct TimeoutMiddleware: ToolMiddleware {
    /// Error thrown when execution times out.
    public struct TimeoutError: Error, LocalizedError {
        public let toolName: String
        public let duration: Duration

        public var errorDescription: String? {
            "Tool '\(toolName)' timed out after \(duration)"
        }
    }

    private let duration: Duration

    /// Creates a timeout middleware.
    ///
    /// - Parameter duration: Maximum execution time.
    public init(duration: Duration) {
        self.duration = duration
    }

    public func handle(_ context: ToolContext, next: @escaping Next) async throws -> ToolResult {
        try await withThrowingTaskGroup(of: ToolResult.self) { group in
            group.addTask {
                try await next(context)
            }

            group.addTask {
                try await Task.sleep(for: self.duration)
                throw TimeoutError(toolName: context.toolName, duration: self.duration)
            }

            let result = try await group.next()!
            group.cancelAll()
            return result
        }
    }
}

// MARK: - PassthroughMiddleware

/// A middleware that does nothing, useful for testing or conditional chains.
public struct PassthroughMiddleware: ToolMiddleware {
    public init() {}

    public func handle(_ context: ToolContext, next: @escaping Next) async throws -> ToolResult {
        try await next(context)
    }
}

// MARK: - ConditionalMiddleware

/// Middleware that conditionally applies another middleware.
///
/// ## Example
///
/// ```swift
/// let pipeline = ToolPipeline()
///     .use(ConditionalMiddleware(
///         condition: { $0.toolName.hasPrefix("dangerous_") },
///         middleware: PermissionMiddleware { _ in false }
///     ))
/// ```
public struct ConditionalMiddleware: ToolMiddleware {
    private let condition: @Sendable (ToolContext) -> Bool
    private let middleware: any ToolMiddleware
    private let otherwise: (any ToolMiddleware)?

    /// Creates a conditional middleware.
    ///
    /// - Parameters:
    ///   - condition: Condition to check.
    ///   - middleware: Middleware to apply if condition is true.
    ///   - otherwise: Optional middleware to apply if condition is false.
    public init(
        condition: @escaping @Sendable (ToolContext) -> Bool,
        middleware: any ToolMiddleware,
        otherwise: (any ToolMiddleware)? = nil
    ) {
        self.condition = condition
        self.middleware = middleware
        self.otherwise = otherwise
    }

    public func handle(_ context: ToolContext, next: @escaping Next) async throws -> ToolResult {
        if condition(context) {
            return try await middleware.handle(context, next: next)
        } else if let otherwise = otherwise {
            return try await otherwise.handle(context, next: next)
        } else {
            return try await next(context)
        }
    }
}
