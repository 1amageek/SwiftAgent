//
//  Pipeline.swift
//  SwiftAgent
//
//  Created by SwiftAgent on 2025/01/09.
//

import Foundation

/// A container that executes steps sequentially.
///
/// `Pipeline` provides a named container for composing steps using
/// the `@StepBuilder` result builder. It serves the same purpose as
/// the implicit composition in `Agent.body`, but can be used anywhere
/// a `Step` is expected.
///
/// ## Basic Usage
///
/// ```swift
/// let pipeline = Pipeline {
///     Transform { input in input.uppercased() }
///     ProcessingStep()
///     Transform { output in output.trimmingCharacters(in: .whitespaces) }
/// }
///
/// let result = try await pipeline.run("hello")
/// ```
///
/// ## With Gates
///
/// ```swift
/// Pipeline {
///     // Entry gate: validate and transform input
///     Gate { input in
///         guard !input.isEmpty else {
///             return .block(reason: "Empty input")
///         }
///         return .pass(input.lowercased())
///     }
///
///     // Main processing
///     MyAgent()
///
///     // Exit gate: post-process output
///     Gate { output in
///         .pass(output.trimmingCharacters(in: .whitespaces))
///     }
/// }
/// ```
///
/// ## Session Integration
///
/// ```swift
/// try await Pipeline {
///     Gate { input in .pass(enrichWithContext(input)) }
///     GenerateText(session: session) { Prompt($0) }
///     Gate { output in .pass(sanitize(output)) }
/// }
/// .session(session)
/// .run("Hello")
/// ```
public struct Pipeline<Content: Step>: Step {
    public typealias Input = Content.Input
    public typealias Output = Content.Output

    private let content: Content

    /// Creates a pipeline with the given content.
    ///
    /// - Parameter content: A closure that builds the pipeline content
    ///   using `@StepBuilder` syntax.
    public init(@StepBuilder content: () -> Content) {
        self.content = content()
    }

    @discardableResult
    public func run(_ input: Input) async throws -> Output {
        try await content.run(input)
    }
}

// MARK: - Convenience Extensions

extension Pipeline {

    /// Creates an empty pipeline that passes input through unchanged.
    ///
    /// - Returns: A pipeline that does nothing.
    public static func empty<T: Sendable>() -> Pipeline<EmptyStep<T>> where Content == EmptyStep<T> {
        Pipeline<EmptyStep<T>> { EmptyStep<T>() }
    }
}
