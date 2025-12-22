//
//  PipelineWrappedTool.swift
//  SwiftAgent
//
//  Created by SwiftAgent on 2025/01/15.
//

import Foundation
import OpenFoundationModels
import OpenFoundationModelsCore

/// A type-erased tool wrapper that routes execution through the ToolExecutionPipeline.
///
/// This wrapper allows any `Tool` to be wrapped and have its execution intercepted
/// by the pipeline's hooks, permission checks, timeout, and retry logic.
///
/// ## Usage
///
/// ```swift
/// let pipeline = ToolExecutionPipeline(options: .withLogging())
/// let wrapped = PipelineWrappedAnyTool(
///     wrapping: myTool,
///     pipeline: pipeline,
///     contextProvider: { await session.createToolContext() },
///     onToolExecuted: { toolName in await store.recordToolCall(toolName) }
/// )
/// ```
public struct PipelineWrappedAnyTool: Tool, @unchecked Sendable {

    public typealias Arguments = GeneratedContent
    public typealias Output = String

    /// The name of the wrapped tool.
    public let name: String

    /// The description of the wrapped tool.
    public let description: String

    /// The JSON schema for the tool's parameters.
    public let parameters: GenerationSchema

    /// Whether to include schema in instructions.
    public let includesSchemaInInstructions: Bool

    /// The type-erased execution closure.
    private let executor: @Sendable (GeneratedContent) async throws -> String

    /// Creates a pipeline-wrapped tool.
    ///
    /// - Parameters:
    ///   - tool: The tool to wrap.
    ///   - pipeline: The execution pipeline to use.
    ///   - contextProvider: A closure that provides the execution context.
    ///   - onToolExecuted: Optional callback invoked after successful execution with the tool name.
    public init<T: Tool>(
        wrapping tool: T,
        pipeline: ToolExecutionPipeline,
        contextProvider: @escaping @Sendable () async -> ToolExecutionContext,
        onToolExecuted: (@Sendable (String) async -> Void)? = nil
    ) {
        self.name = tool.name
        self.description = tool.description
        self.parameters = tool.parameters
        self.includesSchemaInInstructions = tool.includesSchemaInInstructions

        let toolName = tool.name

        // Capture the tool and pipeline in a type-erased closure
        self.executor = { [tool, pipeline] arguments in
            // Get the execution context
            let context = await contextProvider()

            // Get timeout from pipeline options
            let timeout = pipeline.options.timeout(for: toolName)

            // Execute with timeout
            let result = try await withThrowingTaskGroup(of: String.self) { group in
                // Add the main operation task
                group.addTask {
                    // Convert GeneratedContent to the tool's typed arguments
                    let typedArgs = try T.Arguments(arguments)

                    // Execute through the pipeline
                    let output = try await pipeline.execute(
                        tool: tool,
                        arguments: typedArgs,
                        context: context
                    )

                    // Convert output to string representation
                    return output.promptRepresentation.description
                }

                // Add a timeout task
                group.addTask {
                    try await Task.sleep(for: timeout)
                    throw ToolExecutionError.timeout(duration: timeout)
                }

                // Wait for the first task to complete
                guard let result = try await group.next() else {
                    throw ToolExecutionError.unknown
                }

                // Cancel any remaining tasks
                group.cancelAll()

                return result
            }

            // Record the tool call after successful execution
            await onToolExecuted?(toolName)

            return result
        }
    }

    /// Executes the wrapped tool through the pipeline.
    ///
    /// - Parameter arguments: The arguments as GeneratedContent.
    /// - Returns: The tool output as a string.
    public func call(arguments: GeneratedContent) async throws -> String {
        do {
            return try await executor(arguments)
        } catch ToolExecutionError.fallbackRequested(let fallbackOutput) {
            // Handle fallback: return the fallback output string directly
            // This is caught here because the wrapper's Output is String, making it type-safe
            return fallbackOutput
        }
    }
}

// MARK: - Array Extension for Wrapping Tools

extension Array where Element == any Tool {

    /// Wraps all tools in the array with pipeline execution.
    ///
    /// - Parameters:
    ///   - pipeline: The execution pipeline to use.
    ///   - contextProvider: A closure that provides the execution context.
    ///   - onToolExecuted: Optional callback invoked after successful execution with the tool name.
    /// - Returns: An array of pipeline-wrapped tools.
    public func wrapped(
        with pipeline: ToolExecutionPipeline,
        contextProvider: @escaping @Sendable () async -> ToolExecutionContext,
        onToolExecuted: (@Sendable (String) async -> Void)? = nil
    ) -> [any Tool] {
        self.map { tool in
            wrapTool(tool, pipeline: pipeline, contextProvider: contextProvider, onToolExecuted: onToolExecuted)
        }
    }
}

// MARK: - Helper Function for Type Erasure

/// Wraps a type-erased tool with pipeline execution.
///
/// This function uses runtime type casting to handle the existential Tool.
private func wrapTool(
    _ tool: any Tool,
    pipeline: ToolExecutionPipeline,
    contextProvider: @escaping @Sendable () async -> ToolExecutionContext,
    onToolExecuted: (@Sendable (String) async -> Void)?
) -> any Tool {
    // We need to use a helper that can extract the concrete type
    return _wrapToolImpl(tool, pipeline: pipeline, contextProvider: contextProvider, onToolExecuted: onToolExecuted)
}

/// Implementation helper that wraps a tool by creating a closure-based wrapper.
private func _wrapToolImpl(
    _ tool: any Tool,
    pipeline: ToolExecutionPipeline,
    contextProvider: @escaping @Sendable () async -> ToolExecutionContext,
    onToolExecuted: (@Sendable (String) async -> Void)?
) -> any Tool {
    // Create a wrapper that captures the tool's execution
    return _AnyToolWrapper(
        tool: tool,
        pipeline: pipeline,
        contextProvider: contextProvider,
        onToolExecuted: onToolExecuted
    )
}

/// Internal wrapper that handles type-erased tools.
private struct _AnyToolWrapper: Tool, @unchecked Sendable {
    typealias Arguments = GeneratedContent
    typealias Output = String

    let name: String
    let description: String
    let parameters: GenerationSchema
    let includesSchemaInInstructions: Bool

    private let wrappedTool: any Tool
    private let pipeline: ToolExecutionPipeline
    private let contextProvider: @Sendable () async -> ToolExecutionContext
    private let onToolExecuted: (@Sendable (String) async -> Void)?

    init(
        tool: any Tool,
        pipeline: ToolExecutionPipeline,
        contextProvider: @escaping @Sendable () async -> ToolExecutionContext,
        onToolExecuted: (@Sendable (String) async -> Void)?
    ) {
        self.name = tool.name
        self.description = tool.description
        self.parameters = tool.parameters
        self.includesSchemaInInstructions = tool.includesSchemaInInstructions
        self.wrappedTool = tool
        self.pipeline = pipeline
        self.contextProvider = contextProvider
        self.onToolExecuted = onToolExecuted
    }

    func call(arguments: GeneratedContent) async throws -> String {
        let context = await contextProvider()

        // Get timeout from pipeline options
        let timeout = pipeline.options.timeout(for: name)

        do {
            // Execute with timeout
            let result = try await withTimeout(timeout) {
                try await executeWithPipeline(
                    tool: wrappedTool,
                    arguments: arguments,
                    pipeline: pipeline,
                    context: context
                )
            }

            // Record the tool call after successful execution
            await onToolExecuted?(name)

            return result
        } catch ToolExecutionError.fallbackRequested(let fallbackOutput) {
            // Handle fallback: return the fallback output string directly
            // This is caught here because the wrapper's Output is String, making it type-safe
            await onToolExecuted?(name)
            return fallbackOutput
        }
    }

    /// Executes an operation with a timeout.
    private func withTimeout(
        _ timeout: Duration,
        operation: @Sendable @escaping () async throws -> String
    ) async throws -> String {
        try await withThrowingTaskGroup(of: String.self) { group in
            // Add the main operation task
            group.addTask {
                try await operation()
            }

            // Add a timeout task
            group.addTask {
                try await Task.sleep(for: timeout)
                throw ToolExecutionError.timeout(duration: timeout)
            }

            // Wait for the first task to complete
            guard let result = try await group.next() else {
                throw ToolExecutionError.unknown
            }

            // Cancel any remaining tasks
            group.cancelAll()

            return result
        }
    }
}

/// Executes a type-erased tool through the pipeline.
private func executeWithPipeline(
    tool: any Tool,
    arguments: GeneratedContent,
    pipeline: ToolExecutionPipeline,
    context: ToolExecutionContext
) async throws -> String {
    // Use runtime helper to execute with the correct type
    return try await _executeTypedTool(tool, arguments: arguments, pipeline: pipeline, context: context)
}

/// Helper function that uses generics to execute the tool with proper typing.
private func _executeTypedTool<T: Tool>(
    _ tool: T,
    arguments: GeneratedContent,
    pipeline: ToolExecutionPipeline,
    context: ToolExecutionContext
) async throws -> String {
    let typedArgs = try T.Arguments(arguments)
    let output = try await pipeline.execute(tool: tool, arguments: typedArgs, context: context)
    return output.promptRepresentation.description
}
