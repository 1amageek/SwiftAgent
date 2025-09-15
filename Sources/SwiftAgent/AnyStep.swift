//
//  AnyStep.swift
//  SwiftAgent
//
//  Created by Claude Code on 2025/01/26.
//

import Foundation

/// Type-erased wrapper for Step protocol
///
/// `AnyStep` allows multiple steps with the same input and output types to be stored
/// in the same collection or used interchangeably, even if their concrete types differ.
///
/// This is essential for `Parallel`, `Race`, and other collection-based step operations
/// where we need to work with heterogeneous step types that share common input/output types.
///
/// Example:
/// ```swift
/// let steps: [AnyStep<String, Int>] = [
///     AnyStep(Transform { $0.count }),
///     AnyStep(Transform { Int($0) ?? 0 })
/// ]
/// ```
public struct AnyStep<In: Sendable, Out: Sendable>: Step, Sendable {
    
    public typealias Input = In
    public typealias Output = Out
    
    private let _run: @Sendable (In) async throws -> Out
    
    /// Creates a type-erased step from any concrete step
    ///
    /// - Parameter step: The concrete step to wrap
    public init<S: Step & Sendable>(_ step: S) where S.Input == In, S.Output == Out {
        self._run = step.run
    }
    
    /// Executes the wrapped step
    ///
    /// - Parameter input: The input to pass to the wrapped step
    /// - Returns: The output from the wrapped step
    /// - Throws: Any error thrown by the wrapped step
    @discardableResult
    public func run(_ input: In) async throws -> Out {
        try await _run(input)
    }
}

/// Extension to make AnyStep creation more convenient
extension Step where Self: Sendable {
    /// Creates a type-erased version of this step
    ///
    /// - Returns: An `AnyStep` wrapping this step
    public func eraseToAnyStep() -> AnyStep<Input, Output> {
        AnyStep(self)
    }
}