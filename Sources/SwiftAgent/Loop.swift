//
//  Loop.swift
//  SwiftAgent
//
//  Created by Norikazu Muramoto on 2025/01/21.
//


import Foundation

/// A step that repeatedly executes another step until a condition is met or indefinitely.
///
/// The `Loop` step provides two main ways of operation:
/// 1. Finite loop with a condition and maximum iterations
/// 2. Infinite loop that continues until manually stopped
///
/// Example of finite loop:
/// ```swift
/// Loop(max: 5) { input in
///     Transform { value in
///         value + 1
///     }
/// } until: {
///     Transform { value in
///         value >= 10
///     }
/// }
/// ```
///
/// Example of infinite loop:
/// ```swift
/// Loop { input in
///     WaitForInput(prompt: "Enter command: ")
///     Transform { command in
///         processCommand(command)
///     }
/// }
/// ```
public struct Loop<S: Step>: Step where S.Input == S.Output {
    
    /// The input type for the loop step
    public typealias Input = S.Input
    
    /// The output type for the loop step
    public typealias Output = S.Output
    
    /// Defines the type of loop operation
    private enum LoopType {
        /// A loop that runs for a maximum number of iterations
        case finite(Int)
        
        /// A loop that runs indefinitely
        case infinite
    }
    
    /// The type of loop operation to perform
    private let loopType: LoopType
    
    /// The step to execute in each iteration
    private let step: @Sendable (Input) -> S

    /// Optional condition to check for loop termination
    private let condition: (@Sendable () -> any Step<S.Output, Bool>)?
    
    /// Create a finite loop with a maximum number of iterations and termination condition
    ///
    /// - Parameters:
    ///   - max: Maximum number of iterations
    ///   - step: The step to execute in each iteration
    ///   - condition: Condition to check for loop termination
    public init(
        max: Int,
        @StepBuilder step: @escaping @Sendable (Input) -> S,
        @StepBuilder until condition: @escaping @Sendable () -> any Step<S.Output, Bool>
    ) {
        precondition(max > 0, "Maximum iterations must be greater than 0")
        self.loopType = .finite(max)
        self.step = step
        self.condition = condition
    }

    /// Create a loop with only a termination condition (uses a default max of Int.max)
    ///
    /// - Parameters:
    ///   - step: The step to execute in each iteration
    ///   - condition: Condition to check for loop termination
    public init(
        @StepBuilder step: @escaping @Sendable (Input) -> S,
        @StepBuilder until condition: @escaping @Sendable () -> any Step<S.Output, Bool>
    ) {
        self.loopType = .infinite
        self.step = step
        self.condition = condition
    }

    /// Create an infinite loop
    ///
    /// - Parameter step: The step to execute in each iteration
    public init(
        @StepBuilder step: @escaping @Sendable (Input) -> S
    ) {
        self.loopType = .infinite
        self.step = step
        self.condition = nil
    }
    
    /// Execute the loop with the given input
    ///
    /// - Parameter input: Initial input value
    /// - Returns: Final output value
    /// - Throws: 
    ///   - `LoopError.conditionNotMet` if maximum iterations reached in finite loop
    ///   - `LoopError.cancelled` if the task was cancelled
    ///   - Any error thrown by the executed step or condition
    @discardableResult
    public func run(_ input: Input) async throws -> Output {
        var current = input
        
        switch loopType {
        case .finite(let max):
            for iteration in 0..<max {
                // Check for task cancellation
                try Task.checkCancellation()
                try TurnCancellationContext.current?.checkCancellation()

                // Execute the step
                let output = try await step(current).run(current)
                
                // Check termination condition
                if let condition = condition,
                   try await condition().run(output) {
                    return output
                }
                
                // Update current value for next iteration
                current = output
                
                // Optional: you can add iteration tracking here
                if !Task.isCancelled {
                    try await reportProgress(iteration: iteration, max: max)
                }
            }
            throw LoopError.conditionNotMet
            
        case .infinite:
            while true {
                // Check for task cancellation
                try Task.checkCancellation()
                try TurnCancellationContext.current?.checkCancellation()

                // Execute the step
                let output = try await step(current).run(current)
                
                // Check termination condition if provided
                if let condition = condition,
                   try await condition().run(output) {
                    return output
                }
                
                // Update current value for next iteration
                current = output
                
                // Optional: you can add iteration tracking here
                if !Task.isCancelled {
                    try await reportProgress(iteration: nil, max: nil)
                }
            }
        }
    }
    
    /// Report progress of the loop execution
    ///
    /// This is a placeholder for progress reporting functionality.
    /// You can implement custom progress tracking by overriding this method.
    ///
    /// - Parameters:
    ///   - iteration: Current iteration number (if finite loop)
    ///   - max: Maximum iterations (if finite loop)
    private func reportProgress(iteration: Int?, max: Int?) async throws {
        // Placeholder for progress reporting
        // You can implement custom progress tracking here
    }
}

/// Errors that can occur during loop execution
public enum LoopError: Error, LocalizedError {
    /// Indicates that the maximum iterations were reached without meeting the condition
    case conditionNotMet
    
    /// Indicates that the loop was cancelled
    case cancelled
    
    public var errorDescription: String? {
        switch self {
        case .conditionNotMet:
            return "Maximum iterations reached without meeting the termination condition"
        case .cancelled:
            return "Loop execution was cancelled"
        }
    }
}

// MARK: - Helper Functions

extension Loop {
    /// Create a loop with a simple boolean condition
    ///
    /// This convenience initializer allows creating a loop with a simple boolean condition
    /// rather than a full Step-based condition.
    ///
    /// Example:
    /// ```swift
    /// Loop(max: 5, step: someStep, while: { value in
    ///     value < 10
    /// })
    /// ```
    ///
    /// - Parameters:
    ///   - max: Maximum number of iterations
    ///   - step: The step to execute in each iteration
    ///   - condition: Simple boolean condition for loop continuation (returns true to continue)
    public init(
        max: Int,
        @StepBuilder step: @escaping @Sendable (Input) -> S,
        while condition: @escaping @Sendable (S.Output) -> Bool
    ) {
        self.init(max: max, step: step) {
            Transform { output in
                !condition(output)  // Invert because Loop expects true to stop
            }
        }
    }

    /// Create a loop with a simple boolean termination condition
    ///
    /// This convenience initializer allows creating a loop with a simple boolean condition
    /// that determines when to stop the loop.
    ///
    /// Example:
    /// ```swift
    /// Loop(max: 5, step: someStep, until: { value in
    ///     value >= 10
    /// })
    /// ```
    ///
    /// - Parameters:
    ///   - max: Maximum number of iterations
    ///   - step: The step to execute in each iteration
    ///   - stopCondition: Simple boolean condition for loop termination (returns true to stop)
    public init(
        max: Int,
        @StepBuilder step: @escaping @Sendable (Input) -> S,
        until stopCondition: @escaping @Sendable (S.Output) -> Bool
    ) {
        self.init(max: max, step: step) {
            Transform { output in
                stopCondition(output)
            }
        }
    }

    /// Create an infinite loop with a simple boolean continuation condition
    ///
    /// Example:
    /// ```swift
    /// Loop(step: someStep, while: { value in
    ///     value < 10
    /// })
    /// ```
    ///
    /// - Parameters:
    ///   - step: The step to execute in each iteration
    ///   - condition: Simple boolean condition for loop continuation (returns true to continue)
    public init(
        @StepBuilder step: @escaping @Sendable (Input) -> S,
        while condition: @escaping @Sendable (S.Output) -> Bool
    ) {
        self.init(step: step) {
            Transform { output in
                !condition(output)  // Invert because Loop expects true to stop
            }
        }
    }

    /// Create an infinite loop with a simple boolean termination condition
    ///
    /// Example:
    /// ```swift
    /// Loop(step: someStep, until: { value in
    ///     value >= 10
    /// })
    /// ```
    ///
    /// - Parameters:
    ///   - step: The step to execute in each iteration
    ///   - stopCondition: Simple boolean condition for loop termination (returns true to stop)
    public init(
        @StepBuilder step: @escaping @Sendable (Input) -> S,
        until stopCondition: @escaping @Sendable (S.Output) -> Bool
    ) {
        self.init(step: step) {
            Transform { output in
                stopCondition(output)
            }
        }
    }
}

// MARK: - Async Sequence Support
//
// Note: AsyncSequence support has been temporarily removed due to 
// incompatible constraints. Loop steps need S.Input == S.Output 
// while AsyncSequence requires different semantics.
// This can be re-implemented with a separate LoopSequence type if needed.

// MARK: - Custom String Convertible

extension Loop: CustomStringConvertible {
    public var description: String {
        switch loopType {
        case .finite(let max):
            return "Loop(max: \(max))"
        case .infinite:
            return "Loop(infinite)"
        }
    }
}

// MARK: - Custom Debug String Convertible

extension Loop: CustomDebugStringConvertible {
    public var debugDescription: String {
        switch loopType {
        case .finite(let max):
            return "Loop<\(S.self)>(max: \(max), hasCondition: \(condition != nil))"
        case .infinite:
            return "Loop<\(S.self)>(infinite)"
        }
    }
}
