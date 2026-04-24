//
//  ToolExecutor.swift
//  SwiftAgent
//
//  Created by SwiftAgent on 2026/04/23.
//

import Foundation

// MARK: - ToolMatch

/// A lightweight description of a tool returned from a runtime search.
///
/// `ToolMatch` intentionally decouples search results from the concrete
/// `Tool` protocol so that Gateway tools (e.g. `ToolSearchTool`) can render
/// results without importing every tool implementation.
public struct ToolMatch: Sendable, Hashable {
    /// The tool's registered name. Use this to invoke the tool via
    /// `ToolExecutor.execute(toolName:argumentsJSON:)`.
    public let name: String

    /// A short human-readable description of the tool.
    public let description: String

    /// The score assigned by the search backend. Higher is better.
    public let score: Double

    /// JSON-encoded input schema string, if available.
    ///
    /// `ToolSearchTool` includes this in its output so that the LLM can
    /// immediately understand the tool's argument shape and invoke it
    /// without an additional discovery round-trip.
    public let parametersJSON: String?

    public init(name: String, description: String, score: Double, parametersJSON: String? = nil) {
        self.name = name
        self.description = description
        self.score = score
        self.parametersJSON = parametersJSON
    }
}

// MARK: - ToolExecutor

/// An abstraction over the tool runtime that Gateway tools can depend on.
///
/// Gateway tools (tools that dispatch further tool calls) read the current
/// executor from `ToolExecutorContext.current` at call time. This avoids
/// passing the runtime by construction and keeps Gateway tools free of
/// lifetime coupling with the runtime.
///
/// Every `execute` call goes through the same middleware pipeline, which
/// means a Gateway tool's dispatched invocations automatically receive the
/// same permission checks, sandboxing, and observability as direct tool
/// calls from the LLM.
public protocol ToolExecutor: Sendable {
    /// Executes a registered tool by name.
    ///
    /// - Parameters:
    ///   - toolName: The registered tool name.
    ///   - argumentsJSON: A JSON-encoded argument payload. Decoding happens
    ///     inside the middleware chain's leaf, so any middleware (permission,
    ///     sandbox, plugin) runs before deserialization.
    /// - Returns: The tool's `String` output.
    /// - Throws: `ToolRuntimeError.unknownTool` if no tool with the given
    ///   name is registered, or any error raised by middleware/the tool.
    func execute(toolName: String, argumentsJSON: String) async throws -> String

    /// Searches the registered tools for matches to the given query.
    ///
    /// - Parameters:
    ///   - query: A free-form query string. Implementations may rank by
    ///     name, description, or more advanced heuristics.
    ///   - topN: The maximum number of matches to return.
    /// - Returns: Matches ordered from most to least relevant.
    func search(query: String, topN: Int) async throws -> [ToolMatch]
}

// MARK: - ToolExecutorContext

/// TaskLocal storage for the current `ToolExecutor`.
///
/// Gateway tools read `ToolExecutorContext.current` to dispatch further
/// tool calls through the runtime. The runtime sets this value before
/// invoking the middleware chain, so any code running inside a middleware
/// or a leaf tool can access it without construction-time injection.
///
/// ## Example
///
/// ```swift
/// struct MyGatewayTool: Tool {
///     func call(arguments: Args) async throws -> Output {
///         guard let executor = ToolExecutorContext.current else {
///             throw ToolRuntimeError.executorUnavailable
///         }
///         let result = try await executor.execute(
///             toolName: arguments.dispatch,
///             argumentsJSON: arguments.payload
///         )
///         return Output(result: result)
///     }
/// }
/// ```
public enum ToolExecutorContext {
    /// The current executor, if one has been installed by the runtime.
    @TaskLocal
    public static var current: (any ToolExecutor)?

    /// Executes an operation with the given executor installed as
    /// `ToolExecutorContext.current`.
    public static func withValue<T: Sendable>(
        _ executor: any ToolExecutor,
        operation: () async throws -> T
    ) async rethrows -> T {
        try await $current.withValue(executor, operation: operation)
    }
}

// MARK: - ToolRuntimeError

/// Errors raised by `ToolRuntime` and related tooling.
public enum ToolRuntimeError: Error, LocalizedError {
    /// The tool name does not resolve to a registered tool.
    case unknownTool(String)

    /// A Gateway tool attempted to use `ToolExecutorContext.current` while
    /// no executor was installed.
    case executorUnavailable

    /// Argument type mismatch during deserialization inside the runtime.
    case argumentTypeMismatch(expected: String, received: String)

    /// Middleware short-circuited without invoking the leaf tool for a
    /// typed execution. A typed execution must always reach the leaf so
    /// that a concrete output value can be produced.
    case middlewareShortCircuited(toolName: String)

    public var errorDescription: String? {
        switch self {
        case .unknownTool(let name):
            return "No tool registered with name '\(name)'"
        case .executorUnavailable:
            return "ToolExecutorContext.current is not set. Gateway tools must be invoked through a ToolRuntime."
        case .argumentTypeMismatch(let expected, let received):
            return "Argument type mismatch: expected \(expected), received \(received)"
        case .middlewareShortCircuited(let toolName):
            return "Middleware short-circuited without executing tool '\(toolName)'. For typed tools, all middleware must call next()."
        }
    }
}
