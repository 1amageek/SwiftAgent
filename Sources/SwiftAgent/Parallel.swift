//
//  ParallelStepBuilder.swift
//  SwiftAgent
//
//  Created by Norikazu Muramoto on 2025/01/25.
//

import Foundation

/// A step that executes multiple child steps in parallel and collects successful results.
///
/// `Parallel` implements a **best-effort** strategy: it collects all successful results
/// while tolerating individual step failures. This is ideal for data aggregation and
/// resilient processing patterns.
///
/// ## Use Cases
///
/// ### Data Aggregation
/// ```swift
/// let parallel = Parallel<Query, SearchResult> {
///     SearchGitHub()              // May be temporarily down
///     SearchStackOverflow()
///     SearchDocumentation()
/// }
/// // Returns results from successful sources, even if GitHub fails
/// ```
///
/// ### Best-Effort Processing
/// ```swift
/// let parallel = Parallel<[URL], ResizedImage> {
///     ResizeImage(size: .thumbnail)
///     ResizeImage(size: .medium)
///     ResizeImage(size: .large)
/// }
/// // Processes all valid images, skips corrupted ones
/// ```
///
/// ## Behavior
/// - Executes all steps concurrently
/// - Collects all **successful** results
/// - Continues even if some steps fail
/// - Only throws if **all** steps fail
/// - Results are returned in completion order (not declaration order)
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
    
    /// Runs all steps concurrently and collects successful results.
    ///
    /// This method implements a **best-effort** strategy:
    /// - Executes all steps in parallel
    /// - Collects all successful results
    /// - Tolerates individual step failures
    /// - Only throws if all steps fail
    ///
    /// - Parameter input: The input to pass to each step.
    /// - Returns: An array of successful outputs (in completion order).
    /// - Throws:
    ///   - `ParallelError.allStepsFailed` if all steps fail.
    ///   - `ParallelError.noResults` if no steps were provided.
    @discardableResult
    public func run(_ input: Input) async throws -> [ElementOutput] {
        // Use Result to capture both successes and failures without throwing
        let outcome: Result<[ElementOutput], Error> = await withTaskGroup(
            of: Result<ElementOutput, Error>.self
        ) { group in
            // Launch all steps in parallel
            for step in steps {
                group.addTask { @Sendable in
                    do {
                        let output = try await step.run(input)
                        return .success(output)
                    } catch {
                        return .failure(error)
                    }
                }
            }

            var results: [ElementOutput] = []
            var errors: [Error] = []

            // Collect all results, separating successes from failures
            for await result in group {
                switch result {
                case .success(let output):
                    results.append(output)
                case .failure(let error):
                    errors.append(error)
                }
            }

            // Return partial results if any succeeded
            if !results.isEmpty {
                return .success(results)
            }

            // All steps failed
            return .failure(
                errors.isEmpty
                    ? ParallelError.noResults
                    : ParallelError.allStepsFailed(errors)
            )
        }

        return try outcome.get()
    }
}

/// Errors that can occur during parallel execution.
public enum ParallelError: Error {
    /// No steps produced results
    case noResults
    
    /// All steps failed with errors
    case allStepsFailed([Error])
}
