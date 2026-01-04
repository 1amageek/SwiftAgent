//
//  Race.swift
//  SwiftAgent
//
//  Created by Norikazu Muramoto on 2025/01/25.
//


import Foundation

/// A step that executes multiple steps concurrently and returns the first successful result.
///
/// `Race` implements a **success-first** strategy: it waits for the first step to succeed,
/// ignoring any failures from other steps. This is ideal for fallback and redundancy patterns.
///
/// ## Use Cases
///
/// ### Fallback Pattern
/// ```swift
/// let race = Race<URL, Data> {
///     FetchFromPrimaryServer()    // Main server (sometimes down)
///     FetchFromMirrorServer()     // Mirror (slower but stable)
///     FetchFromCDN()              // CDN (fast if cached)
/// }
/// // Returns the first successful response, even if primary fails fast
/// ```
///
/// ### Redundant LLM Providers
/// ```swift
/// let race = Race<String, String> {
///     GenerateWithOpenAI()        // May hit rate limits
///     GenerateWithAnthropic()     // May timeout under load
///     GenerateWithLocal()         // Slow but reliable
/// }
/// ```
///
/// ## Behavior
/// - Returns the first **successful** result
/// - Continues waiting if a step fails (other steps may still succeed)
/// - Only throws if **all** steps fail
/// - Cancels remaining steps once a success is found
///
/// - Note: If a timeout is specified and no step succeeds before the timeout, the race fails with `.timeout`.
public struct Race<Input: Sendable, Output: Sendable>: Step {
    
    private let steps: [AnyStep<Input, Output>]
    private let timeout: Duration?
    
    /// Creates a `Race` without a timeout.
    ///
    /// - Parameter builder: A result builder that produces an array of steps to run in parallel.
    public init(@ParallelStepBuilder builder: () -> [AnyStep<Input, Output>]) {
        self.steps = builder()
        self.timeout = nil
    }
    
    /// Creates a `Race` with a timeout.
    ///
    /// - Parameters:
    ///   - timeout: The maximum duration to wait before failing the race.
    ///   - builder: A result builder that produces an array of steps to run in parallel.
    public init(
        timeout: Duration,
        @ParallelStepBuilder builder: () -> [AnyStep<Input, Output>]
    ) {
        self.steps = builder()
        self.timeout = timeout
    }
    
    /// Runs all steps concurrently and returns the first successful result.
    ///
    /// This method implements a **success-first** strategy:
    /// - Waits for the first step to succeed
    /// - Ignores failures from other steps (they may still be running)
    /// - Only throws if all steps fail or timeout occurs
    ///
    /// - Parameter input: The input to pass to each step.
    /// - Returns: The output of the first step to complete successfully.
    /// - Throws:
    ///   - The last error if all steps fail (preserves original error type).
    ///   - `RaceError.timeout` if the timeout elapses before any step succeeds.
    ///   - `RaceError.noSuccessfulResults` if no steps were provided.
    @discardableResult
    public func run(_ input: Input) async throws -> Output {
        let outcome: Result<Output, Error> = await withTaskGroup(
            of: RaceResultType<Output>.self
        ) { group in
            // Add a timeout task if needed
            if let t = timeout {
                group.addTask {
                    try? await Task.sleep(for: t)
                    return .timeout
                }
            }

            // Launch each step in the group
            for step in steps {
                group.addTask { @Sendable in
                    do {
                        let output = try await step.run(input)
                        return .stepResult(.success(output))
                    } catch {
                        return .stepResult(.failure(error))
                    }
                }
            }

            var lastError: Error = RaceError.noSuccessfulResults

            // Wait for the first success, or timeout
            for await raceResult in group {
                switch raceResult {
                case .timeout:
                    // Timeout fires - cancel everything and fail immediately
                    group.cancelAll()
                    return .failure(RaceError.timeout)

                case .stepResult(.success(let output)):
                    // Found a success - cancel remaining tasks and return
                    group.cancelAll()
                    return .success(output)

                case .stepResult(.failure(let error)):
                    // Record the error but continue waiting for potential successes
                    lastError = error
                }
            }

            // All steps failed - return the last error (preserves original error type)
            return .failure(lastError)
        }

        return try outcome.get()
    }
}

/// Errors that can occur during a `Race` execution.
public enum RaceError: Error {
    /// No step completed successfully.
    case noSuccessfulResults
    /// The race timed out before any step completed.
    case timeout
}

/// Internal type used by Race to distinguish between step results and timeout.
enum RaceResultType<Output: Sendable>: Sendable {
    case stepResult(Result<Output, Error>)
    case timeout
}
