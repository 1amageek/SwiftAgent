//
//  ToolExecutionOptions.swift
//  SwiftAgent
//
//  Created by SwiftAgent on 2025/01/15.
//

import Foundation

/// Configuration options for individual tool execution.
///
/// These options can be set per-tool to customize timeout, retry behavior,
/// approval requirements, and hooks.
public struct ToolExecutionOptions: Sendable {

    /// Timeout for this tool's execution.
    ///
    /// If nil, the global default timeout is used.
    public var timeout: Duration?

    /// Retry configuration for this tool.
    ///
    /// If nil, the global default retry configuration is used.
    public var retry: RetryConfiguration?

    /// Whether this tool requires user approval before execution.
    public var requiresApproval: Bool

    /// The permission level of this tool.
    public var permissionLevel: ToolPermissionLevel

    /// Hooks specific to this tool.
    ///
    /// These are executed in addition to global hooks.
    public var hooks: [any ToolExecutionHook]

    /// Creates tool execution options.
    ///
    /// - Parameters:
    ///   - timeout: Timeout duration for execution.
    ///   - retry: Retry configuration.
    ///   - requiresApproval: Whether approval is required.
    ///   - permissionLevel: The permission level.
    ///   - hooks: Tool-specific hooks.
    public init(
        timeout: Duration? = nil,
        retry: RetryConfiguration? = nil,
        requiresApproval: Bool = false,
        permissionLevel: ToolPermissionLevel = .standard,
        hooks: [any ToolExecutionHook] = []
    ) {
        self.timeout = timeout
        self.retry = retry
        self.requiresApproval = requiresApproval
        self.permissionLevel = permissionLevel
        self.hooks = hooks
    }

    /// Default options with standard settings.
    public static let `default` = ToolExecutionOptions()

    /// Options for read-only tools with no timeout concerns.
    public static let readOnly = ToolExecutionOptions(
        timeout: .seconds(30),
        permissionLevel: .readOnly
    )

    /// Options for tools that modify files.
    public static let fileModification = ToolExecutionOptions(
        timeout: .seconds(60),
        permissionLevel: .elevated
    )

    /// Options for command execution tools.
    public static let commandExecution = ToolExecutionOptions(
        timeout: .seconds(120),
        requiresApproval: true,
        permissionLevel: .dangerous
    )
}

// MARK: - RetryConfiguration

/// Configuration for automatic retry of failed tool executions.
public struct RetryConfiguration: Sendable {

    /// Maximum number of retry attempts.
    public var maxAttempts: Int

    /// Base delay between retries.
    public var baseDelay: Duration

    /// Strategy for calculating retry delays.
    public var strategy: RetryStrategy

    /// Optional predicate to determine if an error should trigger a retry.
    ///
    /// If nil, all errors trigger retries.
    public var shouldRetry: (@Sendable (Error) -> Bool)?

    /// Creates a retry configuration.
    ///
    /// - Parameters:
    ///   - maxAttempts: Maximum retry attempts. Default is 3.
    ///   - baseDelay: Base delay between retries. Default is 1 second.
    ///   - strategy: Retry delay strategy. Default is exponential backoff.
    ///   - shouldRetry: Optional predicate for error filtering.
    public init(
        maxAttempts: Int = 3,
        baseDelay: Duration = .seconds(1),
        strategy: RetryStrategy = .exponentialBackoff(multiplier: 2.0),
        shouldRetry: (@Sendable (Error) -> Bool)? = nil
    ) {
        self.maxAttempts = maxAttempts
        self.baseDelay = baseDelay
        self.strategy = strategy
        self.shouldRetry = shouldRetry
    }

    /// Default retry configuration.
    public static let `default` = RetryConfiguration()

    /// No retries.
    public static let none = RetryConfiguration(maxAttempts: 1)

    /// Aggressive retry configuration for transient errors.
    public static let aggressive = RetryConfiguration(
        maxAttempts: 5,
        baseDelay: .milliseconds(500),
        strategy: .exponentialBackoff(multiplier: 1.5)
    )
}

// MARK: - RetryStrategy

/// Strategy for calculating retry delays.
public enum RetryStrategy: Sendable {
    /// Fixed delay between retries.
    case fixed

    /// Exponential backoff: delay multiplies each attempt.
    ///
    /// - Parameter multiplier: The multiplier for each attempt.
    case exponentialBackoff(multiplier: Double)

    /// Linear backoff: delay increases by a fixed amount each attempt.
    ///
    /// - Parameter increment: The duration to add each attempt.
    case linearBackoff(increment: Duration)

    /// Calculates the delay for a given attempt number.
    ///
    /// - Parameters:
    ///   - attempt: The attempt number (1-based).
    ///   - baseDelay: The base delay duration.
    /// - Returns: The delay for this attempt.
    public func delay(for attempt: Int, baseDelay: Duration) -> Duration {
        switch self {
        case .fixed:
            return baseDelay

        case .exponentialBackoff(let multiplier):
            let factor = pow(multiplier, Double(attempt - 1))
            let seconds = Double(baseDelay.components.seconds)
            let attoseconds = Double(baseDelay.components.attoseconds) / 1e18
            let totalSeconds = (seconds + attoseconds) * factor
            return .nanoseconds(Int64(totalSeconds * 1_000_000_000))

        case .linearBackoff(let increment):
            let incrementSeconds = Double(increment.components.seconds)
            let incrementAtto = Double(increment.components.attoseconds) / 1e18
            let totalIncrement = (incrementSeconds + incrementAtto) * Double(attempt - 1)
            let baseSeconds = Double(baseDelay.components.seconds)
            let baseAtto = Double(baseDelay.components.attoseconds) / 1e18
            let totalSeconds = baseSeconds + baseAtto + totalIncrement
            return .nanoseconds(Int64(totalSeconds * 1_000_000_000))
        }
    }
}

// MARK: - Duration Extensions

extension Duration {
    /// Multiplies a duration by a double value.
    static func * (lhs: Duration, rhs: Double) -> Duration {
        let seconds = Double(lhs.components.seconds)
        let attoseconds = Double(lhs.components.attoseconds) / 1e18
        let totalSeconds = (seconds + attoseconds) * rhs
        return .nanoseconds(Int64(totalSeconds * 1_000_000_000))
    }

    /// Multiplies a duration by an integer value.
    static func * (lhs: Duration, rhs: Int) -> Duration {
        lhs * Double(rhs)
    }

    /// Adds two durations together.
    static func + (lhs: Duration, rhs: Duration) -> Duration {
        let lhsNanos = Int64(lhs.components.seconds) * 1_000_000_000 + lhs.components.attoseconds / 1_000_000_000
        let rhsNanos = Int64(rhs.components.seconds) * 1_000_000_000 + rhs.components.attoseconds / 1_000_000_000
        return .nanoseconds(lhsNanos + rhsNanos)
    }
}
