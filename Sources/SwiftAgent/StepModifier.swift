//
//  StepModifier.swift
//  SwiftAgent
//
//  Created by Norikazu Muramoto on 2025/01/21.
//

import Foundation

/// A protocol that modifies the behavior of a Step.
public protocol StepModifier: Sendable {
    /// The input type of the Step being modified
    associatedtype Input: Sendable
    
    /// The output type of the Step being modified
    associatedtype Output: Sendable
    
    /// The type of the modified step's output (can be different from Output)
    associatedtype ModifiedOutput: Sendable
    
    /// Modifies the step's execution
    /// - Parameters:
    ///   - input: The input to the step
    ///   - step: A closure that executes the original step
    /// - Returns: The modified output
    func body(input: Input, step: @escaping (Input) async throws -> Output) async throws -> ModifiedOutput
}

/// A Step that applies a modifier to another Step
public struct ModifiedStep<S: Step, M: StepModifier>: Step 
where S.Input == M.Input, S.Output == M.Output {
    public typealias Input = S.Input
    public typealias Output = M.ModifiedOutput
    
    private let step: S
    private let modifier: M
    
    public init(step: S, modifier: M) {
        self.step = step
        self.modifier = modifier
    }
    
    @discardableResult
    public func run(_ input: Input) async throws -> Output {
        try await modifier.body(input: input) { input in
            try await step.run(input)
        }
    }
}

/// Extension to add modifier support to all Steps
extension Step {
    /// Applies a modifier to this step
    public func modifier<M: StepModifier>(_ modifier: M) -> ModifiedStep<Self, M> 
    where M.Input == Input, M.Output == Output {
        ModifiedStep(step: self, modifier: modifier)
    }
}