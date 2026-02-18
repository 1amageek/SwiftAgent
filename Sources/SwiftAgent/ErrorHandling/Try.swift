//
//  Try.swift
//  SwiftAgent
//
//  Created by SwiftAgent on 2025/01/07.
//

import Foundation

/// A step that provides declarative try-catch error handling.
///
/// `Try` allows you to handle errors declaratively, specifying both
/// the primary step and a fallback step to execute on error.
///
/// ## Usage
///
/// ```swift
/// struct ResearchAgent: Step {
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
public struct Try<TryStep: Step, CatchStep: Step>: Step
where TryStep.Input == CatchStep.Input, TryStep.Output == CatchStep.Output {

    public typealias Input = TryStep.Input
    public typealias Output = TryStep.Output

    private let tryStep: TryStep
    private let catchStepBuilder: @Sendable (Error) -> CatchStep

    /// Creates a try-catch step with error parameter.
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

extension Try: Sendable where TryStep: Sendable, CatchStep: Sendable {}

// MARK: - Error-Ignoring Initializer

extension Try where CatchStep: Sendable {
    /// Creates a try-catch step that ignores the error.
    ///
    /// - Parameters:
    ///   - tryBuilder: A builder that produces the primary step.
    ///   - catchBuilder: A closure that returns a fallback step.
    public init(
        @StepBuilder _ tryBuilder: () -> TryStep,
        `catch` catchBuilder: @escaping @Sendable () -> CatchStep
    ) {
        self.tryStep = tryBuilder()
        self.catchStepBuilder = { @Sendable _ in catchBuilder() }
    }
}
