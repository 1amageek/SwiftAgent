//
//  Context.swift
//  SwiftAgent
//
//  Created by SwiftAgent on 2025/01/02.
//

import Foundation

// MARK: - ContextKey Protocol

/// A protocol that defines a key for TaskLocal-based context propagation.
///
/// Requires a `defaultValue` to ensure that context access never fails.
///
/// ## Usage
///
/// ```swift
/// // Define a context key
/// enum URLTrackerContext: ContextKey {
///     @TaskLocal private static var _current: URLTracker?
///
///     static var defaultValue: URLTracker { URLTracker() }
///
///     static var current: URLTracker { _current ?? defaultValue }
///
///     static func withValue<T: Sendable>(
///         _ value: URLTracker,
///         operation: () async throws -> T
///     ) async rethrows -> T {
///         try await $_current.withValue(value, operation: operation)
///     }
/// }
///
/// // Use in a Step
/// struct MyStep: Step {
///     @Context var tracker: URLTracker
///
///     func run(_ input: URL) async throws -> Bool {
///         return !tracker.visitedURLs.contains(input)
///     }
/// }
///
/// // Provide the context
/// let tracker = URLTracker()
/// try await withContext(URLTrackerContext.self, value: tracker) {
///     try await MyStep().run(url)
/// }
/// ```
public protocol ContextKey {
    associatedtype Value: Sendable

    /// The default value when no context is provided.
    static var defaultValue: Value { get }

    /// The current value from TaskLocal storage, falling back to `defaultValue`.
    static var current: Value { get }

    /// Runs an operation with the given value in context.
    static func withValue<T: Sendable>(
        _ value: Value,
        operation: () async throws -> T
    ) async rethrows -> T
}

// MARK: - Context Property Wrapper

/// A property wrapper that provides access to a value from the TaskLocal context.
///
/// ## Usage
///
/// ```swift
/// struct CrawlerStep: Step {
///     @Context var tracker: URLTracker
///
///     func run(_ input: URL) async throws -> CrawlResult {
///         guard !tracker.visitedURLs.contains(input) else {
///             return .alreadyVisited
///         }
///         tracker.markVisited(input)
///         // ...
///     }
/// }
/// ```
@propertyWrapper
public struct Context<Value: Contextable>: Sendable {

    public init() {}

    public var wrappedValue: Value {
        Value.ContextKeyType.current
    }
}

// MARK: - Context Runner

/// Runs an async operation with a context value available.
///
/// ## Usage
///
/// ```swift
/// let tracker = URLTracker()
/// let result = try await withContext(URLTrackerContext.self, value: tracker) {
///     try await myCrawlerStep.run(startURL)
/// }
/// ```
///
/// - Parameters:
///   - key: The context key type.
///   - value: The value to make available in context.
///   - operation: The async operation to run with the context.
/// - Returns: The result of the operation.
func withContext<Key: ContextKey, T: Sendable>(
    _ key: Key.Type,
    value: Key.Value,
    operation: () async throws -> T
) async rethrows -> T {
    try await Key.withValue(value, operation: operation)
}

// MARK: - ContextStep

/// A Step wrapper that provides a context value during execution.
public struct ContextStep<S: Step, Key: ContextKey>: Step {
    public typealias Input = S.Input
    public typealias Output = S.Output

    private let step: S
    private let value: Key.Value

    public init(step: S, key: Key.Type, value: Key.Value) {
        self.step = step
        self.value = value
    }

    @discardableResult
    public func run(_ input: Input) async throws -> Output {
        try await withContext(Key.self, value: value) {
            try await step.run(input)
        }
    }
}

// MARK: - Step Extension

extension Step {

    /// Provides a context value for this step.
    ///
    /// ```swift
    /// try await myStep
    ///     .context(config)
    ///     .run(input)
    /// ```
    public func context<T: Contextable>(
        _ value: T
    ) -> ContextStep<Self, T.ContextKeyType> {
        ContextStep(step: self, key: T.ContextKeyType.self, value: value)
    }
}

// MARK: - Example Context Key Implementation
//
// To create a custom context, define an enum conforming to ContextKey:
//
// ```swift
// enum URLTrackerContext: ContextKey {
//     @TaskLocal private static var _current: URLTracker?
//
//     static var defaultValue: URLTracker { URLTracker() }
//
//     static var current: URLTracker { _current ?? defaultValue }
//
//     static func withValue<T: Sendable>(
//         _ value: URLTracker,
//         operation: () async throws -> T
//     ) async rethrows -> T {
//         try await $_current.withValue(value, operation: operation)
//     }
// }
// ```
