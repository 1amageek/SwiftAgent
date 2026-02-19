//
//  RetryStep.swift
//  SwiftAgent
//
//  Created by SwiftAgent on 2025/01/07.
//

import Foundation

/// A step that automatically retries a wrapped step on failure.
///
/// `RetryStep` wraps another step and will retry execution up to a specified
/// number of attempts if the step throws an error. An optional delay can be
/// added between retry attempts.
///
/// ## Usage
///
/// ```swift
/// // Retry 3 times with no delay
/// FetchDataStep()
///     .retry(3)
///
/// // Retry 3 times with 1 second delay between attempts
/// FetchDataStep()
///     .retry(3, delay: .seconds(1))
///
/// // Combined with timeout
/// FetchDataStep()
///     .timeout(.seconds(5))
///     .retry(3, delay: .seconds(1))
/// ```
///
/// ## Behavior
///
/// - Attempts the step up to `attempts` times
/// - If the step succeeds on any attempt, returns the result
/// - If all attempts fail, throws the last error
/// - Respects task cancellation between retries
///
/// ## Example with Timeout
///
/// ```swift
/// // Each attempt has its own 5-second timeout
/// // Total maximum time: ~18 seconds (3 attempts * 5s + 2 delays * 1s)
/// FetchDataStep()
///     .timeout(.seconds(5))
///     .retry(3, delay: .seconds(1))
/// ```
public struct RetryStep<S: Step>: Step {
    public typealias Input = S.Input
    public typealias Output = S.Output

    private let step: S
    private let attempts: Int
    private let delay: Duration?

    /// Creates a retry step.
    ///
    /// - Parameters:
    ///   - step: The step to wrap.
    ///   - attempts: The maximum number of attempts (minimum 1).
    ///   - delay: An optional delay between retry attempts.
    public init(step: S, attempts: Int, delay: Duration? = nil) {
        self.step = step
        self.attempts = max(1, attempts)
        self.delay = delay
    }

    /// Runs the wrapped step with automatic retries.
    ///
    /// - Parameter input: The input to pass to the wrapped step.
    /// - Returns: The output from the wrapped step on the first successful attempt.
    /// - Throws: The last error if all attempts fail, or `CancellationError` if cancelled.
    @discardableResult
    public func run(_ input: Input) async throws -> Output {
        var lastError: Error?

        for attempt in 1...attempts {
            // Check for cancellation before each attempt
            try Task.checkCancellation()

            do {
                return try await step.run(input)
            } catch is CancellationError {
                // Don't retry on cancellation
                throw CancellationError()
            } catch {
                lastError = error

                // Add delay before next attempt (if not the last attempt)
                if attempt < attempts, let delay = delay {
                    try await Task.sleep(for: delay)
                }
            }
        }

        // All attempts failed, throw the last error
        // Force unwrap is safe because we always set lastError on failure
        throw lastError!
    }
}


