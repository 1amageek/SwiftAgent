//
//  Race.swift
//  SwiftAgent
//
//  Created by Norikazu Muramoto on 2025/01/25.
//


import Foundation

/// A step that executes multiple steps concurrently and returns the first successful result.
/// Optionally applies a timeout to the race.
/// - Note: If a timeout is specified and no step completes before the timeout, the race fails with `.timeout`.
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
    /// - Parameter input: The input to pass to each step.
    /// - Returns: The output of the first step to complete successfully.
    /// - Throws:
    ///   - `RaceError.noSuccessfulResults` if no step succeeds.
    ///   - `RaceError.timeout` if the timeout elapses before any step succeeds.
    public func run(_ input: Input) async throws -> Output {
        try await withThrowingTaskGroup(of: Output.self) { group in
            // Launch each step in the group
            for step in steps {
                group.addTask { @Sendable in
                    try await step.run(input)
                }
            }
            // Add a timeout task if needed
            if let t = timeout {
                group.addTask {
                    try await Task.sleep(for: t)
                    throw RaceError.timeout
                }
            }
            
            // Return the first successful result or throw if none
            do {
                guard let result = try await group.next() else {
                    throw RaceError.noSuccessfulResults
                }
                group.cancelAll()
                return result
            } catch {
                group.cancelAll()
                throw error
            }
        }
    }
}

/// Errors that can occur during a `Race` execution.
public enum RaceError: Error {
    /// No step completed successfully.
    case noSuccessfulResults
    /// The race timed out before any step completed.
    case timeout
}
