//
//  TryCatch.swift
//  SwiftAgent
//
//  Created by SwiftAgent on 2025/01/07.
//

import Foundation

/// A step that provides declarative try-catch error handling.
///
/// `TryCatch` allows you to handle errors declaratively, specifying both
/// the primary step and a fallback step to execute on error.
///
/// ## Usage
///
/// ```swift
/// struct ResearchAgent: Agent {
///     var body: some Step<Query, Report> {
///         Try {
///             FetchStep()
///                 .timeout(.seconds(10))
///         } catch: { error in
///             FallbackStep()
///         }
///
///         ProcessStep()
///     }
/// }
/// ```
///
/// ## Error-Ignoring Variant
///
/// When you don't need to inspect the error:
///
/// ```swift
/// Try {
///     FetchFromPrimary()
/// } catch: {
///     FetchFromBackup()
/// }
/// ```
public struct TryCatch<TryStep: Step, CatchStep: Step>: Step
where TryStep.Input == CatchStep.Input, TryStep.Output == CatchStep.Output {

    public typealias Input = TryStep.Input
    public typealias Output = TryStep.Output

    private let tryStep: TryStep
    private let catchStepBuilder: @Sendable (Error) -> CatchStep

    /// Creates a try-catch step.
    ///
    /// - Parameters:
    ///   - tryBuilder: A builder that produces the primary step.
    ///   - catchBuilder: A closure that receives an error and returns a fallback step.
    public init(
        @StepBuilder _ tryBuilder: () -> TryStep,
        `catch` catchBuilder: @escaping @Sendable (Error) -> CatchStep
    ) {
        self.tryStep = tryBuilder()
        self.catchStepBuilder = catchBuilder
    }

    /// Runs the try step, executing the catch step if an error occurs.
    ///
    /// - Parameter input: The input to pass to both steps.
    /// - Returns: The output from either the try step or catch step.
    /// - Throws: Any error thrown by the catch step.
    @discardableResult
    public func run(_ input: Input) async throws -> Output {
        do {
            return try await tryStep.run(input)
        } catch {
            let catchStep = catchStepBuilder(error)
            return try await catchStep.run(input)
        }
    }
}

// MARK: - Sendable Conformance

extension TryCatch: Sendable where TryStep: Sendable, CatchStep: Sendable {}

// MARK: - Global Function (with error parameter)

/// Creates a try-catch step for declarative error handling.
///
/// ## Usage
///
/// ```swift
/// var body: some Step<Query, Report> {
///     Try {
///         FetchStep()
///             .timeout(.seconds(10))
///     } catch: { error in
///         FallbackStep()
///     }
///
///     ProcessStep()
/// }
/// ```
///
/// The same input is passed to both the try step and catch step.
///
/// - Parameters:
///   - tryBuilder: A builder that produces the primary step.
///   - catchBuilder: A closure that receives an error and returns a fallback step.
/// - Returns: A `TryCatch` step.
public func Try<TryStep: Step, CatchStep: Step>(
    @StepBuilder _ tryBuilder: () -> TryStep,
    `catch` catchBuilder: @escaping @Sendable (Error) -> CatchStep
) -> TryCatch<TryStep, CatchStep>
where TryStep.Input == CatchStep.Input, TryStep.Output == CatchStep.Output {
    TryCatch(tryBuilder, catch: catchBuilder)
}

// MARK: - Global Function (without error parameter)

/// Creates a try-catch step with a fallback that ignores the error.
///
/// ## Usage
///
/// ```swift
/// Try {
///     FetchFromPrimary()
/// } catch: {
///     FetchFromBackup()
/// }
/// ```
///
/// - Parameters:
///   - tryBuilder: A builder that produces the primary step.
///   - catchBuilder: A closure that returns a fallback step.
/// - Returns: A `TryCatch` step.
public func Try<TryStep: Step, CatchStep: Step & Sendable>(
    @StepBuilder _ tryBuilder: () -> TryStep,
    `catch` catchBuilder: @escaping @Sendable () -> CatchStep
) -> TryCatch<TryStep, CatchStep>
where TryStep.Input == CatchStep.Input, TryStep.Output == CatchStep.Output {
    TryCatch(tryBuilder) { @Sendable _ in
        catchBuilder()
    }
}
