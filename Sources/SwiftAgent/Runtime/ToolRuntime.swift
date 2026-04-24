//
//  ToolRuntime.swift
//  SwiftAgent
//
//  Created by SwiftAgent on 2026/04/23.
//

import Foundation
import Synchronization

// MARK: - ToolRuntime

/// The runtime that drives tool execution through a middleware chain.
///
/// `ToolRuntime` is built from a `ToolRuntimeConfiguration` and is
/// immutable afterwards. It exposes two views onto the same registry:
///
/// - ``publicTools()`` returns type-erased forwarder tools for the LLM.
///   Every invocation is routed back through `execute(toolName:argumentsJSON:)`
///   so middleware always runs and `ToolExecutorContext.current` is set.
/// - ``execute(toolName:argumentsJSON:)`` is called directly by Gateway tools
///   (e.g. `ToolSearchTool`) to dispatch further tool invocations.
///
/// Because the registry is written once at init and read many times during
/// execution, no actor or lock is required; all stored properties are `let`.
public final class ToolRuntime: ToolExecutor, Sendable {

    // MARK: - Stored State (immutable)

    /// The ordered middleware list.
    private let middleware: [any ToolMiddleware]

    /// All registered tools keyed by name. Includes both public and hidden.
    private let toolsByName: [String: any Tool]

    /// Public tools as registered. Used to construct forwarders.
    private let publicToolDescriptors: [PublicToolDescriptor]

    // MARK: - Init

    public init(configuration: ToolRuntimeConfiguration) {
        self.middleware = configuration.middleware

        var table: [String: any Tool] = [:]
        for tool in configuration.publicTools {
            precondition(
                table[tool.name] == nil,
                "Duplicate tool name '\(tool.name)' in runtime configuration. Ensure each tool name is unique across both public and hidden tools."
            )
            table[tool.name] = tool
        }
        for tool in configuration.hiddenTools {
            precondition(
                table[tool.name] == nil,
                "Duplicate tool name '\(tool.name)' in runtime configuration. Ensure each tool name is unique across both public and hidden tools."
            )
            table[tool.name] = tool
        }
        self.toolsByName = table

        self.publicToolDescriptors = configuration.publicTools.map { tool in
            PublicToolDescriptor(
                name: tool.name,
                description: tool.description,
                parameters: tool.parameters,
                includesSchemaInInstructions: tool.includesSchemaInInstructions
            )
        }
    }

    // MARK: - Public API

    /// Returns type-erased forwarder tools that the LLM can see and invoke.
    ///
    /// Each forwarder, when called, routes the invocation back through
    /// `execute(toolName:argumentsJSON:)`. This guarantees the middleware
    /// chain always runs and `ToolExecutorContext.current` is set for the
    /// duration of the call.
    public func publicTools() -> [any Tool] {
        publicToolDescriptors.map { descriptor in
            PublicForwarderTool(descriptor: descriptor, runtime: self)
        }
    }

    // MARK: - ToolExecutor

    public func execute(toolName: String, argumentsJSON: String) async throws -> String {
        guard let tool = toolsByName[toolName] else {
            throw ToolRuntimeError.unknownTool(toolName)
        }

        return try await ToolExecutorContext.withValue(self) {
            try await MiddlewareChain.executeLeaf(
                tool: tool,
                argumentsJSON: argumentsJSON,
                middleware: middleware
            )
        }
    }

    public func search(query: String, topN: Int) async throws -> [ToolMatch] {
        let normalized = query.lowercased()
        let encoder = JSONEncoder()
        encoder.outputFormatting = .sortedKeys

        var matches: [ToolMatch] = []
        for tool in toolsByName.values {
            let score = Self.score(tool: tool, query: normalized)
            guard score > 0 else { continue }

            let data = try encoder.encode(tool.parameters)
            guard let parametersJSON = String(data: data, encoding: .utf8) else {
                throw ToolRuntimeError.argumentTypeMismatch(
                    expected: "UTF-8 JSON",
                    received: "non-UTF-8 data (\(data.count) bytes)"
                )
            }
            matches.append(ToolMatch(
                name: tool.name,
                description: tool.description,
                score: score,
                parametersJSON: parametersJSON
            ))
        }
        return matches
            .sorted { $0.score > $1.score }
            .prefix(max(0, topN))
            .map { $0 }
    }

    // MARK: - Typed Execution Helper

    /// Executes a typed tool through the runtime's middleware chain.
    ///
    /// This variant is available to callers that already hold a typed
    /// `Tool` reference (e.g. unit tests). Prefer
    /// `execute(toolName:argumentsJSON:)` for LLM-driven or name-based
    /// invocations.
    public func execute<T: Tool>(
        _ tool: T,
        arguments: T.Arguments
    ) async throws -> T.Output where T.Arguments: Sendable, T.Output: Sendable {
        try await ToolExecutorContext.withValue(self) {
            try await MiddlewareChain.executeTyped(
                tool: tool,
                arguments: arguments,
                middleware: middleware
            )
        }
    }

    // MARK: - Scoring

    private static func score(tool: any Tool, query: String) -> Double {
        guard !query.isEmpty else { return 0 }

        let name = tool.name.lowercased()
        let description = tool.description.lowercased()

        var score = 0.0
        if name == query {
            score += 10
        } else if name.contains(query) {
            score += 5
        }
        if description.contains(query) {
            score += 2
        }
        // Tokenized match for multi-word queries.
        let tokens = query.split(whereSeparator: { !$0.isLetter && !$0.isNumber })
        for token in tokens where token.count >= 2 {
            let t = String(token)
            if name.contains(t) { score += 1 }
            if description.contains(t) { score += 0.5 }
        }
        return score
    }
}

// MARK: - PublicToolDescriptor

/// A snapshot of a public tool's schema used to construct forwarders.
private struct PublicToolDescriptor: Sendable {
    let name: String
    let description: String
    let parameters: GenerationSchema
    let includesSchemaInInstructions: Bool
}

// MARK: - PublicForwarderTool

/// A type-erased forwarder that the LLM sees in place of the real tool.
///
/// All invocations are routed back through `ToolRuntime.execute` so that
/// the middleware chain always runs and `ToolExecutorContext.current` is
/// installed for Gateway tools that dispatch further tool calls.
private struct PublicForwarderTool: Tool, Sendable {
    typealias Arguments = GeneratedContent
    typealias Output = String

    let name: String
    let description: String
    let parameters: GenerationSchema
    let includesSchemaInInstructions: Bool

    private let runtime: ToolRuntime

    init(descriptor: PublicToolDescriptor, runtime: ToolRuntime) {
        self.name = descriptor.name
        self.description = descriptor.description
        self.parameters = descriptor.parameters
        self.includesSchemaInInstructions = descriptor.includesSchemaInInstructions
        self.runtime = runtime
    }

    func call(arguments: GeneratedContent) async throws -> String {
        try await runtime.execute(toolName: name, argumentsJSON: arguments.jsonString)
    }
}

// MARK: - MiddlewareChain (internal)

/// Drives a middleware chain around a leaf tool invocation.
///
/// This is an implementation detail of `ToolRuntime`. External callers
/// should not depend on it.
internal enum MiddlewareChain {

    /// Runs the chain with a leaf executor. `ToolContext.current` is
    /// propagated via TaskLocal across the leaf.
    static func run(
        context: ToolContext,
        middleware: [any ToolMiddleware],
        leaf: @escaping @Sendable (ToolContext) async throws -> ToolResult
    ) async throws -> ToolResult {
        let leafWithContext: @Sendable (ToolContext) async throws -> ToolResult = { ctx in
            try await ctx.withCurrent {
                try await leaf(ctx)
            }
        }

        guard !middleware.isEmpty else {
            return try await leafWithContext(context)
        }

        var chain: ToolMiddleware.Next = leafWithContext
        for m in middleware.reversed() {
            let currentChain = chain
            chain = { ctx in
                try await m.handle(ctx, next: currentChain)
            }
        }
        return try await chain(context)
    }

    /// Executes a typed tool through the chain.
    static func executeTyped<T: Tool>(
        tool: T,
        arguments: T.Arguments,
        middleware: [any ToolMiddleware]
    ) async throws -> T.Output where T.Arguments: Sendable, T.Output: Sendable {
        let startTime = ContinuousClock.now
        let args = arguments

        let argumentsString = try _encodeArgumentsToJSON(args) ?? String(describing: args)
        let context = ToolContext(
            toolName: tool.name,
            arguments: argumentsString,
            metadata: _toolContextMetadata(for: tool, argumentsJSON: argumentsString)
        )

        let outputBox = Mutex<T.Output?>(nil)

        let result = try await run(context: context, middleware: middleware) { [tool] ctx in
            do {
                let effectiveArgs = try _decodeArguments(ctx.arguments, as: T.Arguments.self, fallback: args)
                let output = try await tool.call(arguments: effectiveArgs)
                outputBox.withLock { $0 = output }
                let duration = ContinuousClock.now - startTime
                return .success(String(describing: output), duration: duration)
            } catch {
                let duration = ContinuousClock.now - startTime
                return .failure(error, duration: duration)
            }
        }

        if let error = result.error {
            throw error
        }

        guard let output = outputBox.withLock({ $0 }) else {
            throw ToolRuntimeError.middlewareShortCircuited(toolName: tool.name)
        }

        return output
    }

    /// Executes the leaf tool (end of the middleware chain) for a name-based
    /// invocation whose arguments arrive as a JSON string.
    ///
    /// Callers pass `any Tool`; Swift opens the existential at the call site
    /// so the implementation can access `T.Arguments`. Pairs with `run(...)`,
    /// which drives the middleware chain around this leaf.
    static func executeLeaf<T: Tool>(
        tool: T,
        argumentsJSON: String,
        middleware: [any ToolMiddleware]
    ) async throws -> String {
        let startTime = ContinuousClock.now

        let context = ToolContext(
            toolName: tool.name,
            arguments: argumentsJSON,
            metadata: _toolContextMetadata(for: tool, argumentsJSON: argumentsJSON)
        )

        let result = try await run(context: context, middleware: middleware) { ctx in
            do {
                let effectiveGeneratedContent = try GeneratedContent(json: ctx.arguments)
                let effectiveArgs = try T.Arguments(effectiveGeneratedContent)
                let output = try await tool.call(arguments: effectiveArgs)
                let duration = ContinuousClock.now - startTime
                return .success(String(describing: output), duration: duration)
            } catch {
                let duration = ContinuousClock.now - startTime
                return .failure(error, duration: duration)
            }
        }

        if let error = result.error {
            throw error
        }
        return result.output
    }
}

// MARK: - Internal Helpers

/// Attempts to encode typed arguments to JSON if they conform to Encodable.
private func _encodeArgumentsToJSON<T>(_ arguments: T) throws -> String? {
    guard let encodable = arguments as? Encodable else {
        return nil
    }
    return try _encodeToJSON(encodable)
}

private func _encodeToJSON(_ value: Encodable) throws -> String {
    let encoder = JSONEncoder()
    encoder.outputFormatting = .sortedKeys
    let data = try encoder.encode(AnyEncodable(value))
    guard let json = String(data: data, encoding: .utf8) else {
        throw ToolRuntimeError.argumentTypeMismatch(
            expected: "UTF-8 JSON",
            received: "non-UTF-8 data (\(data.count) bytes)"
        )
    }
    return json
}

private func _decodeArguments<T: ConvertibleFromGeneratedContent>(
    _ argumentsJSON: String,
    as _: T.Type,
    fallback: T
) throws -> T {
    let generatedContent = try GeneratedContent(json: argumentsJSON)
    do {
        return try T(generatedContent)
    } catch {
        if argumentsJSON == (try _encodeArgumentsToJSON(fallback) ?? String(describing: fallback)) {
            return fallback
        }
        throw error
    }
}

private func _toolContextMetadata(
    for tool: any Tool,
    argumentsJSON: String
) -> [String: String] {
    guard let provider = tool as? any ToolContextMetadataProvider else {
        return [:]
    }
    return provider.toolContextMetadata(argumentsJSON: argumentsJSON)
}

/// Type-erased wrapper for Encodable values.
private struct AnyEncodable: Encodable {
    private let _encode: (Encoder) throws -> Void

    init(_ value: Encodable) {
        self._encode = { encoder in
            try value.encode(to: encoder)
        }
    }

    func encode(to encoder: Encoder) throws {
        try _encode(encoder)
    }
}
