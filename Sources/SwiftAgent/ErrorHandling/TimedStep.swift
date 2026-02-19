//
//  TimedStep.swift
//  SwiftAgent
//
//  Created by SwiftAgent on 2025/01/07.
//

import Foundation

/// A step that enforces a timeout on the execution of a wrapped step.
///
/// `TimedStep` wraps another step and ensures it completes within a specified
/// duration. If the wrapped step does not complete in time, a `StepTimeoutError`
/// is thrown and the step's task is cancelled.
///
/// ## Usage
///
/// ```swift
/// // Using the modifier (recommended)
/// let timedStep = FetchDataStep()
///     .timeout(.seconds(10))
///
/// // Direct initialization
/// let timedStep = TimedStep(
///     step: FetchDataStep(),
///     duration: .seconds(10)
/// )
/// ```
///
/// ## Behavior
///
/// - The wrapped step and a timeout task run concurrently
/// - If the step completes first, its result is returned
/// - If the timeout fires first, `StepTimeoutError` is thrown
/// - The losing task is cancelled via `group.cancelAll()`
///
/// ## Hierarchical Timeouts
///
/// Timeouts operate independently at each level. They do not accumulate
/// or share remaining time.
///
/// ```swift
/// struct Pipeline: Step {
///     var body: some Step<String, String> {
///         Step1().timeout(.seconds(5))   // Individual: 5s
///         Step2()                         // No timeout
///     }
/// }
///
/// Pipeline()
///     .timeout(.seconds(10))  // Overall: 10s (independent)
/// ```
public struct TimedStep<S: Step>: Step {
    public typealias Input = S.Input
    public typealias Output = S.Output

    private let step: S
    private let duration: Duration
    private let stepName: String?

    /// Creates a timed step.
    ///
    /// - Parameters:
    ///   - step: The step to wrap with a timeout.
    ///   - duration: The maximum duration allowed for the step to complete.
    ///   - stepName: An optional name for error reporting.
    public init(step: S, duration: Duration, stepName: String? = nil) {
        self.step = step
        self.duration = duration
        self.stepName = stepName
    }

    /// Runs the wrapped step with a timeout.
    ///
    /// - Parameter input: The input to pass to the wrapped step.
    /// - Returns: The output from the wrapped step if it completes in time.
    /// - Throws: `StepTimeoutError` if the step does not complete within the duration.
    @discardableResult
    public func run(_ input: Input) async throws -> Output {
        // Capture values locally to avoid capturing self in closures
        let step = self.step
        let duration = self.duration
        let stepName = self.stepName

        let outcome: Result<Output, Error> = await withTaskGroup(
            of: TimedStepResult<Output>.self
        ) { group in
            // Add the main step task
            group.addTask { @Sendable in
                do {
                    let output = try await step.run(input)
                    return .success(output)
                } catch {
                    return .failure(error)
                }
            }

            // Add the timeout task
            group.addTask {
                try? await Task.sleep(for: duration)
                return .timeout
            }

            // Wait for the first result
            for await result in group {
                switch result {
                case .success(let output):
                    // Step completed successfully, cancel the timeout task
                    group.cancelAll()
                    return .success(output)
                case .failure(let error):
                    // Step failed, cancel the timeout task and return error
                    group.cancelAll()
                    return .failure(error)
                case .timeout:
                    // Timeout fired first, cancel the step task
                    group.cancelAll()
                    return .failure(StepTimeoutError(duration: duration, stepName: stepName))
                }
            }

            // Should not reach here, but handle gracefully
            return .failure(StepTimeoutError(duration: duration, stepName: stepName))
        }

        return try outcome.get()
    }
}

// MARK: - Internal Result Type

/// Internal type to distinguish between step completion, failure, and timeout.
private enum TimedStepResult<Output: Sendable>: Sendable {
    case success(Output)
    case failure(Error)
    case timeout
}

