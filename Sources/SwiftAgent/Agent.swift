//
//  Agent.swift
//  SwiftAgent
//
//  Created by Norikazu Muramoto on 2025/01/12.
//

import Foundation

/// A protocol representing a single step in a process.
///
/// `Step` takes an input of a specific type and produces an output of another type asynchronously.
///
/// - Note: The input and output types must conform to both  `Sendable` to ensure
///   compatibility with serialization and concurrency.
public protocol Step<Input, Output> {
    
    /// The type of input required by the step.
    associatedtype Input: Sendable
    
    /// The type of output produced by the step.
    associatedtype Output: Sendable
    
    /// Executes the step with the given input and produces an output asynchronously.
    ///
    /// - Parameter input: The input for the step.
    /// - Returns: The output produced by the step.
    /// - Throws: An error if the step fails to execute or the input is invalid.
    @discardableResult
    func run(_ input: Input) async throws -> Output
}

/// Errors that can occur during tool execution.
public enum ToolError: Error {
    
    /// Required parameters are missing.
    case missingParameters([String])
    
    /// Parameters are invalid.
    case invalidParameters(String)
    
    /// Tool execution failed.
    case executionFailed(String)
    
    /// A localized description of the error.
    public var localizedDescription: String {
        switch self {
        case .missingParameters(let params):
            return "Missing required parameters: \(params.joined(separator: ", "))"
        case .invalidParameters(let message):
            return "Invalid parameters: \(message)"
        case .executionFailed(let message):
            return "Execution failed: \(message)"
        }
    }
}

/// A step that does nothing and simply passes the input as the output.
public struct EmptyStep<Input: Sendable>: Step {
    public typealias Output = Input
    
    @inlinable public init() {}
    
    @discardableResult
    public func run(_ input: Input) async throws -> Output {
        input
    }
}

/// A result builder to combine steps into chains.
@resultBuilder
public struct StepBuilder {
    
    public static func buildBlock<Content>(_ content: Content) -> Content where Content: Step {
        content
    }
    
    public static func buildBlock<S1: Step, S2: Step>(_ step1: S1, _ step2: S2) -> Chain2<S1, S2> where S1.Output == S2.Input {
        Chain2(step1, step2)
    }
    
    public static func buildBlock<S1: Step, S2: Step, S3: Step>(_ step1: S1, _ step2: S2, _ step3: S3) -> Chain3<S1, S2, S3> where S1.Output == S2.Input, S2.Output == S3.Input {
        Chain3(step1, step2, step3)
    }
    
    public static func buildBlock<S1: Step, S2: Step, S3: Step, S4: Step>(_ step1: S1, _ step2: S2, _ step3: S3, _ step4: S4) -> Chain4<S1, S2, S3, S4> where S1.Output == S2.Input, S2.Output == S3.Input, S3.Output == S4.Input {
        Chain4(step1, step2, step3, step4)
    }
    
    public static func buildBlock<S1: Step, S2: Step, S3: Step, S4: Step, S5: Step>(_ step1: S1, _ step2: S2, _ step3: S3, _ step4: S4, _ step5: S5) -> Chain5<S1, S2, S3, S4, S5> where S1.Output == S2.Input, S2.Output == S3.Input, S3.Output == S4.Input, S4.Output == S5.Input {
        Chain5(step1, step2, step3, step4, step5)
    }
    
    public static func buildBlock<S1: Step, S2: Step, S3: Step, S4: Step, S5: Step, S6: Step>(_ step1: S1, _ step2: S2, _ step3: S3, _ step4: S4, _ step5: S5, _ step6: S6) -> Chain6<S1, S2, S3, S4, S5, S6> where S1.Output == S2.Input, S2.Output == S3.Input, S3.Output == S4.Input, S4.Output == S5.Input, S5.Output == S6.Input {
        Chain6(step1, step2, step3, step4, step5, step6)
    }
    
    public static func buildBlock<S1: Step, S2: Step, S3: Step, S4: Step, S5: Step, S6: Step, S7: Step>(_ step1: S1, _ step2: S2, _ step3: S3, _ step4: S4, _ step5: S5, _ step6: S6, _ step7: S7) -> Chain7<S1, S2, S3, S4, S5, S6, S7> where S1.Output == S2.Input, S2.Output == S3.Input, S3.Output == S4.Input, S4.Output == S5.Input, S5.Output == S6.Input, S6.Output == S7.Input {
        Chain7(step1, step2, step3, step4, step5, step6, step7)
    }
    
    public static func buildBlock<S1: Step, S2: Step, S3: Step, S4: Step, S5: Step, S6: Step, S7: Step, S8: Step>(_ step1: S1, _ step2: S2, _ step3: S3, _ step4: S4, _ step5: S5, _ step6: S6, _ step7: S7, _ step8: S8) -> Chain8<S1, S2, S3, S4, S5, S6, S7, S8> where S1.Output == S2.Input, S2.Output == S3.Input, S3.Output == S4.Input, S4.Output == S5.Input, S5.Output == S6.Input, S6.Output == S7.Input, S7.Output == S8.Input {
        Chain8(step1, step2, step3, step4, step5, step6, step7, step8)
    }
}
/// A structure that combines two `Step` instances and executes them sequentially.
public struct Chain2<S1: Step, S2: Step>: Step where S1.Output == S2.Input {
    public typealias Input = S1.Input
    public typealias Output = S2.Output
    
    public let step1: S1
    public let step2: S2
    
    @inlinable public init(_ step1: S1, _ step2: S2) {
        self.step1 = step1
        self.step2 = step2
    }
    
    @discardableResult
    public func run(_ input: Input) async throws -> Output {
        let intermediate = try await step1.run(input)
        return try await step2.run(intermediate)
    }
}

/// A structure that combines three `Step` instances and executes them sequentially.
public struct Chain3<S1: Step, S2: Step, S3: Step>: Step where S1.Output == S2.Input, S2.Output == S3.Input {
    public typealias Input = S1.Input
    public typealias Output = S3.Output
    
    public let step1: S1
    public let step2: S2
    public let step3: S3
    
    @inlinable public init(_ step1: S1, _ step2: S2, _ step3: S3) {
        self.step1 = step1
        self.step2 = step2
        self.step3 = step3
    }
    
    @discardableResult
    public func run(_ input: Input) async throws -> Output {
        let intermediate1 = try await step1.run(input)
        let intermediate2 = try await step2.run(intermediate1)
        return try await step3.run(intermediate2)
    }
}

/// A structure that combines four `Step` instances and executes them sequentially.
public struct Chain4<S1: Step, S2: Step, S3: Step, S4: Step>: Step where S1.Output == S2.Input, S2.Output == S3.Input, S3.Output == S4.Input {
    public typealias Input = S1.Input
    public typealias Output = S4.Output
    
    public let step1: S1
    public let step2: S2
    public let step3: S3
    public let step4: S4
    
    @inlinable public init(_ step1: S1, _ step2: S2, _ step3: S3, _ step4: S4) {
        self.step1 = step1
        self.step2 = step2
        self.step3 = step3
        self.step4 = step4
    }
    
    @discardableResult
    public func run(_ input: Input) async throws -> Output {
        let intermediate1 = try await step1.run(input)
        let intermediate2 = try await step2.run(intermediate1)
        let intermediate3 = try await step3.run(intermediate2)
        return try await step4.run(intermediate3)
    }
}

/// A structure that combines five `Step` instances and executes them sequentially.
public struct Chain5<S1: Step, S2: Step, S3: Step, S4: Step, S5: Step>: Step where S1.Output == S2.Input, S2.Output == S3.Input, S3.Output == S4.Input, S4.Output == S5.Input {
    public typealias Input = S1.Input
    public typealias Output = S5.Output
    
    public let step1: S1
    public let step2: S2
    public let step3: S3
    public let step4: S4
    public let step5: S5
    
    @inlinable public init(_ step1: S1, _ step2: S2, _ step3: S3, _ step4: S4, _ step5: S5) {
        self.step1 = step1
        self.step2 = step2
        self.step3 = step3
        self.step4 = step4
        self.step5 = step5
    }
    
    @discardableResult
    public func run(_ input: Input) async throws -> Output {
        let intermediate1 = try await step1.run(input)
        let intermediate2 = try await step2.run(intermediate1)
        let intermediate3 = try await step3.run(intermediate2)
        let intermediate4 = try await step4.run(intermediate3)
        return try await step5.run(intermediate4)
    }
}

/// A structure that combines six `Step` instances and executes them sequentially.
public struct Chain6<S1: Step, S2: Step, S3: Step, S4: Step, S5: Step, S6: Step>: Step where S1.Output == S2.Input, S2.Output == S3.Input, S3.Output == S4.Input, S4.Output == S5.Input, S5.Output == S6.Input {
    public typealias Input = S1.Input
    public typealias Output = S6.Output
    
    public let step1: S1
    public let step2: S2
    public let step3: S3
    public let step4: S4
    public let step5: S5
    public let step6: S6
    
    @inlinable public init(_ step1: S1, _ step2: S2, _ step3: S3, _ step4: S4, _ step5: S5, _ step6: S6) {
        self.step1 = step1
        self.step2 = step2
        self.step3 = step3
        self.step4 = step4
        self.step5 = step5
        self.step6 = step6
    }
    
    @discardableResult
    public func run(_ input: Input) async throws -> Output {
        let intermediate1 = try await step1.run(input)
        let intermediate2 = try await step2.run(intermediate1)
        let intermediate3 = try await step3.run(intermediate2)
        let intermediate4 = try await step4.run(intermediate3)
        let intermediate5 = try await step5.run(intermediate4)
        return try await step6.run(intermediate5)
    }
}

/// A structure that combines seven `Step` instances and executes them sequentially.
public struct Chain7<S1: Step, S2: Step, S3: Step, S4: Step, S5: Step, S6: Step, S7: Step>: Step where S1.Output == S2.Input, S2.Output == S3.Input, S3.Output == S4.Input, S4.Output == S5.Input, S5.Output == S6.Input, S6.Output == S7.Input {
    public typealias Input = S1.Input
    public typealias Output = S7.Output
    
    public let step1: S1
    public let step2: S2
    public let step3: S3
    public let step4: S4
    public let step5: S5
    public let step6: S6
    public let step7: S7
    
    @inlinable public init(_ step1: S1, _ step2: S2, _ step3: S3, _ step4: S4, _ step5: S5, _ step6: S6, _ step7: S7) {
        self.step1 = step1
        self.step2 = step2
        self.step3 = step3
        self.step4 = step4
        self.step5 = step5
        self.step6 = step6
        self.step7 = step7
    }
    
    @discardableResult
    public func run(_ input: Input) async throws -> Output {
        let intermediate1 = try await step1.run(input)
        let intermediate2 = try await step2.run(intermediate1)
        let intermediate3 = try await step3.run(intermediate2)
        let intermediate4 = try await step4.run(intermediate3)
        let intermediate5 = try await step5.run(intermediate4)
        let intermediate6 = try await step6.run(intermediate5)
        return try await step7.run(intermediate6)
    }
}

/// A structure that combines eight `Step` instances and executes them sequentially.
public struct Chain8<S1: Step, S2: Step, S3: Step, S4: Step, S5: Step, S6: Step, S7: Step, S8: Step>: Step where S1.Output == S2.Input, S2.Output == S3.Input, S3.Output == S4.Input, S4.Output == S5.Input, S5.Output == S6.Input, S6.Output == S7.Input, S7.Output == S8.Input {
    public typealias Input = S1.Input
    public typealias Output = S8.Output
    
    public let step1: S1
    public let step2: S2
    public let step3: S3
    public let step4: S4
    public let step5: S5
    public let step6: S6
    public let step7: S7
    public let step8: S8
    
    @inlinable public init(_ step1: S1, _ step2: S2, _ step3: S3, _ step4: S4, _ step5: S5, _ step6: S6, _ step7: S7, _ step8: S8) {
        self.step1 = step1
        self.step2 = step2
        self.step3 = step3
        self.step4 = step4
        self.step5 = step5
        self.step6 = step6
        self.step7 = step7
        self.step8 = step8
    }
    
    @discardableResult
    public func run(_ input: Input) async throws -> Output {
        let intermediate1 = try await step1.run(input)
        let intermediate2 = try await step2.run(intermediate1)
        let intermediate3 = try await step3.run(intermediate2)
        let intermediate4 = try await step4.run(intermediate3)
        let intermediate5 = try await step5.run(intermediate4)
        let intermediate6 = try await step6.run(intermediate5)
        let intermediate7 = try await step7.run(intermediate6)
        return try await step8.run(intermediate7)
    }
}

extension StepBuilder {
    
    public static func buildIf<Content>(_ content: Content?) -> OptionalStep<Content> where Content: Step {
        OptionalStep(content)
    }
    
    public static func buildEither<TrueContent: Step, FalseContent: Step>(
        first: TrueContent
    ) -> ConditionalStep<TrueContent, FalseContent> {
        ConditionalStep(condition: true, first: first, second: nil)
    }
    
    public static func buildEither<TrueContent: Step, FalseContent: Step>(
        second: FalseContent
    ) -> ConditionalStep<TrueContent, FalseContent> {
        ConditionalStep(condition: false, first: nil, second: second)
    }
}

public struct OptionalStep<S: Step>: Step {
    public typealias Input = S.Input
    public typealias Output = S.Output
    
    private let step: S?
    
    public init(_ step: S?) {
        self.step = step
    }
    
    @discardableResult
    public func run(_ input: Input) async throws -> Output {
        guard let step = step else {
            throw OptionalStepError.stepIsNil
        }
        return try await step.run(input)
    }
}

public enum OptionalStepError: Error {
    case stepIsNil
}

public struct ConditionalStep<TrueStep: Step, FalseStep: Step>: Step where TrueStep.Input == FalseStep.Input, TrueStep.Output == FalseStep.Output {
    public typealias Input = TrueStep.Input
    public typealias Output = TrueStep.Output
    
    private let condition: Bool
    private let first: TrueStep?
    private let second: FalseStep?
    
    public init(condition: Bool, first: TrueStep?, second: FalseStep?) {
        self.condition = condition
        self.first = first
        self.second = second
    }
    
    @discardableResult
    public func run(_ input: Input) async throws -> Output {
        if condition, let first = first {
            return try await first.run(input)
        } else if let second = second {
            return try await second.run(input)
        }
        throw ConditionalStepError.noStepAvailable
    }
}

public enum ConditionalStepError: Error {
    case noStepAvailable
}


/// A result builder that constructs an array of steps that can be executed in parallel.
///
/// The parallel step builder provides a declarative syntax for constructing arrays of
/// independent steps that can be executed concurrently, similar to SwiftUI's view builders.
///
/// Example usage:
/// ```swift
/// Parallel<String, Int> {
///     Transform { input in
///         Int(input) ?? 0
///     }
///     Transform { input in
///         input.count
///     }
/// }
/// ```
/// Result builder for creating arrays of steps to execute in parallel.
@resultBuilder
public struct ParallelStepBuilder {
    
    /// Builds a single step into an array.
    ///
    /// - Parameter step: The step to include
    /// - Returns: A single-element array containing the step
    public static func buildBlock<S: Step & Sendable, In, Out>(_ step: S) -> [AnyStep<In, Out>] 
    where S.Input == In, S.Output == Out, In: Sendable, Out: Sendable {
        [AnyStep(step)]
    }
    
    /// Combines multiple steps into an array.
    ///
    /// - Parameter steps: The steps to combine
    /// - Returns: An array containing all steps
    public static func buildBlock<In, Out>(_ steps: AnyStep<In, Out>...) -> [AnyStep<In, Out>] {
        return steps
    }
    
    /// Builds two steps into an array.
    public static func buildBlock<S1: Step & Sendable, S2: Step & Sendable, In, Out>(
        _ step1: S1, _ step2: S2
    ) -> [AnyStep<In, Out>] 
    where S1.Input == In, S1.Output == Out, S2.Input == In, S2.Output == Out, In: Sendable, Out: Sendable {
        [AnyStep(step1), AnyStep(step2)]
    }
    
    /// Builds three steps into an array.
    public static func buildBlock<S1: Step & Sendable, S2: Step & Sendable, S3: Step & Sendable, In, Out>(
        _ step1: S1, _ step2: S2, _ step3: S3
    ) -> [AnyStep<In, Out>] 
    where S1.Input == In, S1.Output == Out, S2.Input == In, S2.Output == Out, 
          S3.Input == In, S3.Output == Out, In: Sendable, Out: Sendable {
        [AnyStep(step1), AnyStep(step2), AnyStep(step3)]
    }
    
    /// Builds four steps into an array.
    public static func buildBlock<S1: Step & Sendable, S2: Step & Sendable, S3: Step & Sendable, S4: Step & Sendable, In, Out>(
        _ step1: S1, _ step2: S2, _ step3: S3, _ step4: S4
    ) -> [AnyStep<In, Out>] 
    where S1.Input == In, S1.Output == Out, S2.Input == In, S2.Output == Out, 
          S3.Input == In, S3.Output == Out, S4.Input == In, S4.Output == Out, In: Sendable, Out: Sendable {
        [AnyStep(step1), AnyStep(step2), AnyStep(step3), AnyStep(step4)]
    }
    
    /// Handles optional steps.
    ///
    /// - Parameter step: The optional step
    /// - Returns: Array containing the step if present, empty array if nil
    public static func buildOptional<In, Out>(_ step: [AnyStep<In, Out>]?) -> [AnyStep<In, Out>] {
        step ?? []
    }
    
    /// Handles the true path of a conditional.
    ///
    /// - Parameter first: The steps to include if condition is true
    /// - Returns: The provided array of steps
    public static func buildEither<In, Out>(first: [AnyStep<In, Out>]) -> [AnyStep<In, Out>] {
        first
    }
    
    /// Handles the false path of a conditional.
    ///
    /// - Parameter second: The steps to include if condition is false
    /// - Returns: The provided array of steps
    public static func buildEither<In, Out>(second: [AnyStep<In, Out>]) -> [AnyStep<In, Out>] {
        second
    }
    
    /// Handles arrays of steps.
    ///
    /// - Parameter components: Array of arrays of steps
    /// - Returns: Flattened array containing all steps
    public static func buildArray<In, Out>(_ components: [[AnyStep<In, Out>]]) -> [AnyStep<In, Out>] {
        components.flatMap { $0 }
    }
}
