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
/// Implement this protocol to create custom context types that can be
/// propagated through the async call tree using `withContext`.
///
/// ## Usage
///
/// ```swift
/// // Define a context key
/// enum URLTrackerContext: ContextKey {
///     @TaskLocal public static var current: URLTracker?
/// }
///
/// // Use in a Step
/// struct MyStep: Step {
///     @Context(URLTrackerContext.self) var tracker: URLTracker
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

    /// The current value from TaskLocal storage.
    static var current: Value? { get }

    /// Runs an operation with the given value in context.
    static func withValue<T: Sendable>(
        _ value: Value,
        operation: () async throws -> T
    ) async rethrows -> T
}

// MARK: - Context Property Wrapper

/// A property wrapper that provides access to a value from the TaskLocal context.
///
/// Use `@Context` to access values that have been provided via `withContext`.
///
/// ## Usage
///
/// ```swift
/// struct CrawlerStep: Step {
///     @Context(URLTrackerContext.self) var tracker: URLTracker
///
///     func run(_ input: URL) async throws -> CrawlResult {
///         guard !tracker.visitedURLs.contains(input) else {
///             return .alreadyVisited
///         }
///         tracker.markVisited(input)
///         // ... crawl logic
///     }
/// }
/// ```
@propertyWrapper
public struct Context<Key: ContextKey>: Sendable {

    public init(_ key: Key.Type = Key.self) {}

    public var wrappedValue: Key.Value {
        guard let value = Key.current else {
            fatalError(
                """
                No \(Key.Value.self) available in current context for \(Key.self).
                Use withContext(\(Key.self).self, value: ...) { } to provide one.
                """
            )
        }
        return value
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
public func withContext<Key: ContextKey, T: Sendable>(
    _ key: Key.Type,
    value: Key.Value,
    operation: () async throws -> T
) async rethrows -> T {
    try await Key.withValue(value, operation: operation)
}

/// Runs an async operation with an optional context value.
///
/// If the value is nil, the operation runs without modifying the context.
///
/// - Parameters:
///   - key: The context key type.
///   - value: The optional value to make available in context.
///   - operation: The async operation to run.
/// - Returns: The result of the operation.
public func withContext<Key: ContextKey, T: Sendable>(
    _ key: Key.Type,
    value: Key.Value?,
    operation: () async throws -> T
) async rethrows -> T {
    if let value {
        return try await Key.withValue(value, operation: operation)
    } else {
        return try await operation()
    }
}

// MARK: - Optional Context

/// A property wrapper that provides optional access to a context value.
///
/// Unlike `@Context`, this wrapper returns `nil` if the context is not available
/// instead of causing a fatal error.
///
/// ## Usage
///
/// ```swift
/// struct OptionalTrackerStep: Step {
///     @OptionalContext(URLTrackerContext.self) var tracker: URLTracker?
///
///     func run(_ input: URL) async throws -> Result {
///         if let tracker {
///             tracker.markVisited(input)
///         }
///         // ... continue without tracker
///     }
/// }
/// ```
@propertyWrapper
public struct OptionalContext<Key: ContextKey>: Sendable {

    public init(_ key: Key.Type = Key.self) {}

    public var wrappedValue: Key.Value? {
        Key.current
    }
}

// MARK: - Step Extension

extension Step {

    /// Runs this step with a context value.
    ///
    /// ## Usage
    ///
    /// ```swift
    /// let result = try await myStep.run(input, context: URLTrackerContext.self, value: tracker)
    /// ```
    public func run<Key: ContextKey>(
        _ input: Input,
        context key: Key.Type,
        value: Key.Value
    ) async throws -> Output {
        try await withContext(key, value: value) {
            try await self.run(input)
        }
    }
}

// MARK: - Example Context Key Implementation
//
// To create a custom context, define an enum conforming to ContextKey:
//
// ```swift
// enum URLTrackerContext: ContextKey {
//     @TaskLocal public static var current: URLTracker?
//
//     public static func withValue<T: Sendable>(
//         _ value: URLTracker,
//         operation: () async throws -> T
//     ) async rethrows -> T {
//         try await $current.withValue(value, operation: operation)
//     }
// }
// ```
