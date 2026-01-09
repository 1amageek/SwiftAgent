//
//  Gate.swift
//  SwiftAgent
//
//  Created by SwiftAgent on 2025/01/09.
//

import Foundation

/// The result of a gate evaluation.
///
/// Gates use this enum to indicate whether execution should continue
/// with a potentially transformed value, or be blocked entirely.
///
/// ## Example
///
/// ```swift
/// Gate { input in
///     if isValid(input) {
///         return .pass(transform(input))
///     } else {
///         return .block(reason: "Invalid input")
///     }
/// }
/// ```
public enum GateResult<T: Sendable>: Sendable {
    /// Continue execution with the given value.
    case pass(T)

    /// Block execution with the given reason.
    case block(reason: String)
}

/// A step that can transform input or block execution.
///
/// `Gate` provides a way to intercept and modify the flow of data
/// through a pipeline. It can either pass data through (optionally
/// transforming it) or block execution entirely.
///
/// ## Basic Usage
///
/// ```swift
/// // Transform input
/// Gate { input in
///     .pass(input.uppercased())
/// }
///
/// // Block based on condition
/// Gate { input in
///     if input.isEmpty {
///         return .block(reason: "Empty input not allowed")
///     }
///     return .pass(input)
/// }
/// ```
///
/// ## In a Pipeline
///
/// ```swift
/// Pipeline {
///     Gate { input in .pass(sanitize(input)) }
///     ProcessingStep()
///     Gate { output in .pass(format(output)) }
/// }
/// ```
public struct Gate<Input: Sendable, Output: Sendable>: Step {

    private let handler: @Sendable (Input) async throws -> GateResult<Output>

    /// Creates a gate with a handler that can transform input to output.
    ///
    /// - Parameter handler: A closure that evaluates the input and returns
    ///   either a transformed output or a block result.
    public init(_ handler: @escaping @Sendable (Input) async throws -> GateResult<Output>) {
        self.handler = handler
    }

    @discardableResult
    public func run(_ input: Input) async throws -> Output {
        switch try await handler(input) {
        case .pass(let output):
            return output
        case .block(let reason):
            throw GateError.blocked(reason: reason)
        }
    }
}

// MARK: - Same Type Convenience

extension Gate where Input == Output {

    /// Creates a gate where input and output are the same type.
    ///
    /// This is a convenience initializer for common cases where the gate
    /// validates or transforms input without changing its type.
    ///
    /// ## Example
    ///
    /// ```swift
    /// Gate<String, String> { input in
    ///     guard !input.isEmpty else {
    ///         return .block(reason: "Empty input")
    ///     }
    ///     return .pass(input.trimmingCharacters(in: .whitespaces))
    /// }
    /// ```
    ///
    /// - Parameter handler: A closure that evaluates and potentially transforms the input.
    public init(transform handler: @escaping @Sendable (Input) async throws -> GateResult<Input>) {
        self.handler = handler
    }
}

// MARK: - Factory Methods

extension Gate {

    /// Creates a gate that simply passes input through unchanged.
    ///
    /// Useful as a placeholder or for conditional gate creation.
    ///
    /// - Returns: A gate that passes input through unchanged.
    public static func passthrough() -> Gate<Input, Input> where Input == Output {
        Gate<Input, Input> { .pass($0) }
    }

    /// Creates a gate that always blocks with the given reason.
    ///
    /// - Parameter reason: The reason for blocking.
    /// - Returns: A gate that always blocks.
    public static func block(reason: String) -> Gate<Input, Output> {
        Gate { _ in .block(reason: reason) }
    }
}

// MARK: - GateError

/// Errors that can occur during gate evaluation.
public enum GateError: Error, LocalizedError, Sendable {
    /// Execution was blocked by a gate.
    case blocked(reason: String)

    public var errorDescription: String? {
        switch self {
        case .blocked(let reason):
            return "Blocked: \(reason)"
        }
    }
}
