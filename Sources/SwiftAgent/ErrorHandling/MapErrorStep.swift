//
//  MapErrorStep.swift
//  SwiftAgent
//
//  Created by SwiftAgent on 2025/01/07.
//

import Foundation

/// A step that transforms errors from a wrapped step.
///
/// `MapErrorStep` wraps another step and applies a transformation to any
/// errors thrown by the wrapped step. This is useful for:
/// - Wrapping errors in domain-specific error types
/// - Adding context to errors
/// - Converting between error types
///
/// ## Usage
///
/// ```swift
/// // Wrap errors in a domain error
/// ParseStep()
///     .mapError { error in
///         DomainError.parseFailed(underlying: error)
///     }
///
/// // Add context to errors
/// FetchStep()
///     .mapError { error in
///         ContextualError(
///             message: "Failed to fetch user data",
///             underlying: error
///         )
///     }
/// ```
///
/// ## Difference from `Try { } catch: { }`
///
/// | Construct | Purpose | Error Behavior |
/// |-----------|---------|----------------|
/// | `.mapError` | Transform error | Always throws (transformed) |
/// | `Try { } catch: { }` | Recovery | Executes fallback step |
///
/// ```swift
/// // .mapError: Transform but always throw
/// step.mapError { error in
///     CustomError(underlying: error)
/// }  // Transformed error is thrown
///
/// // Try-Catch: Recover with fallback step
/// Try {
///     step
/// } catch: { error in
///     FallbackStep()
/// }
/// ```
public struct MapErrorStep<S: Step>: Step {
    public typealias Input = S.Input
    public typealias Output = S.Output

    private let step: S
    private let transform: @Sendable (Error) -> Error

    /// Creates a map error step.
    ///
    /// - Parameters:
    ///   - step: The step to wrap.
    ///   - transform: A closure that transforms errors.
    public init(
        step: S,
        transform: @escaping @Sendable (Error) -> Error
    ) {
        self.step = step
        self.transform = transform
    }

    /// Runs the wrapped step and transforms any errors.
    ///
    /// - Parameter input: The input to pass to the wrapped step.
    /// - Returns: The output from the wrapped step.
    /// - Throws: The transformed error if the step fails.
    @discardableResult
    public func run(_ input: Input) async throws -> Output {
        do {
            return try await step.run(input)
        } catch {
            throw transform(error)
        }
    }
}


