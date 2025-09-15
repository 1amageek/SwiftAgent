//
//  ParallelStepBuilder.swift
//  SwiftAgent
//
//  Created by Norikazu Muramoto on 2025/01/25.
//

import Foundation

/// A step that executes multiple child steps in parallel.
///
/// `Parallel` allows for concurrent execution of multiple steps that share the same input
/// type and output type. The results are collected into an array in the order the steps complete.
///
/// Example:
/// ```swift
/// let parallelStep = Parallel<String, Int> {
///     Transform { $0.count }
///     Transform { Int($0) ?? 0 }
/// }
/// let results = try await parallelStep.run("123") // [3, 123]
/// ```
public struct Parallel<Input: Sendable, ElementOutput: Sendable>: Step {
    public typealias Output = [ElementOutput]
    
    private let steps: [AnyStep<Input, ElementOutput>]
    
    /// Creates a new parallel step with the given builder closure.
    ///
    /// - Parameter builder: A closure that builds the array of steps to execute in parallel
    public init(@ParallelStepBuilder builder: () -> [AnyStep<Input, ElementOutput>]) {
        self.steps = builder()
    }
    
    @discardableResult
    public func run(_ input: Input) async throws -> [ElementOutput] {
        try await withThrowingTaskGroup(of: ElementOutput.self) { group in
            var results: [ElementOutput] = []
            var collectedErrors: [Error] = []
            
            // Launch all steps in parallel
            for step in steps {
                group.addTask { @Sendable in
                    try await step.run(input)
                }
            }
            
            // Collect results as they complete
            do {
                for try await result in group {
                    results.append(result)
                }
            } catch {
                collectedErrors.append(error)
            }
            
            // Only throw if all steps failed
            guard !results.isEmpty else {
                throw collectedErrors.isEmpty
                ? ParallelError.noResults
                : ParallelError.allStepsFailed(collectedErrors)
            }
            
            return results
        }
    }
}

/// Errors that can occur during parallel execution.
public enum ParallelError: Error {
    /// No steps produced results
    case noResults
    
    /// All steps failed with errors
    case allStepsFailed([Error])
}
