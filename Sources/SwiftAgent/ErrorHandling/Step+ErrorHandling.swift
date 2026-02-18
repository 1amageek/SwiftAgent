//
//  Step+ErrorHandling.swift
//  SwiftAgent
//
//  Created by SwiftAgent on 2025/01/07.
//

import Foundation

// MARK: - Timeout Extension (requires Sendable)

extension Step where Self: Sendable {

    /// Adds a timeout to this step.
    ///
    /// If the step does not complete within the specified duration, a
    /// `StepTimeoutError` is thrown and the step's task is cancelled.
    ///
    /// ## Usage
    ///
    /// ```swift
    /// FetchDataStep()
    ///     .timeout(.seconds(10))
    /// ```
    ///
    /// ## Hierarchical Timeouts
    ///
    /// Timeouts operate independently at each level:
    ///
    /// ```swift
    /// struct Pipeline: Step {
    ///     var body: some Step<String, String> {
    ///         Step1().timeout(.seconds(5))   // Individual
    ///         Step2()
    ///     }
    /// }
    ///
    /// Pipeline()
    ///     .timeout(.seconds(10))  // Overall (independent)
    /// ```
    ///
    /// - Parameter duration: The maximum duration allowed for the step.
    /// - Returns: A step that enforces the timeout.
    public func timeout(_ duration: Duration) -> TimedStep<Self> {
        TimedStep(step: self, duration: duration)
    }
}

// MARK: - General Error Handling Extensions

extension Step {

    // MARK: - Retry

    /// Retries this step on failure.
    ///
    /// If the step fails, it will be retried up to the specified number of
    /// attempts. An optional delay can be added between attempts.
    ///
    /// ## Usage
    ///
    /// ```swift
    /// // Retry 3 times
    /// FetchDataStep()
    ///     .retry(3)
    ///
    /// // Retry with delay
    /// FetchDataStep()
    ///     .retry(3, delay: .seconds(1))
    ///
    /// // Combined with timeout
    /// FetchDataStep()
    ///     .timeout(.seconds(5))
    ///     .retry(3, delay: .seconds(1))
    /// ```
    ///
    /// - Parameters:
    ///   - attempts: Maximum number of attempts (minimum 1).
    ///   - delay: Optional delay between retry attempts.
    /// - Returns: A step that retries on failure.
    public func retry(_ attempts: Int, delay: Duration? = nil) -> RetryStep<Self> {
        RetryStep(step: self, attempts: attempts, delay: delay)
    }

    // MARK: - Map Error

    /// Transforms errors from this step.
    ///
    /// Use this to wrap errors in domain-specific types or add context.
    ///
    /// ## Usage
    ///
    /// ```swift
    /// // Wrap in domain error
    /// ParseStep()
    ///     .mapError { error in
    ///         DomainError.parseFailed(underlying: error)
    ///     }
    ///
    /// // Add context
    /// FetchStep()
    ///     .mapError { error in
    ///         ContextualError(
    ///             message: "Failed to fetch user data",
    ///             underlying: error
    ///         )
    ///     }
    /// ```
    ///
    /// - Parameter transform: A closure that transforms the error.
    /// - Returns: A step that transforms errors.
    public func mapError(
        _ transform: @escaping @Sendable (Error) -> Error
    ) -> MapErrorStep<Self> {
        MapErrorStep(step: self, transform: transform)
    }
}
