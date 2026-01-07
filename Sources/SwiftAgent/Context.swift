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
/// This follows SwiftUI's `EnvironmentKey` pattern, requiring a `defaultValue`
/// to ensure that context access never fails.
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
/// Use `@Context` to access values that have been provided via `withContext`.
/// If no context is provided, the `defaultValue` defined in the `ContextKey` is returned.
///
/// ## Design Note
///
/// This follows SwiftUI's `@Environment` pattern. Unlike earlier versions that would
/// crash when a context was missing, this now relies on `defaultValue` to ensure
/// safe access in all cases.
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
///
/// // Provide context via withContext
/// try await withContext(URLTrackerContext.self, value: tracker) {
///     try await CrawlerStep().run(url)
/// }
/// ```
@propertyWrapper
public struct Context<Key: ContextKey>: Sendable {

    public init(_ key: Key.Type = Key.self) {}

    public var wrappedValue: Key.Value {
        Key.current
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
