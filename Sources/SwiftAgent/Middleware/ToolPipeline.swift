//
//  ToolPipeline.swift
//  SwiftAgent
//
//  Created by SwiftAgent on 2025/01/23.
//

import Foundation

/// A pipeline that chains middleware for tool execution.
///
/// The pipeline applies middleware in order, with each middleware
/// able to intercept and modify the execution flow.
///
/// ## Example
///
/// ```swift
/// let pipeline = ToolPipeline()
///     .use(LoggingMiddleware())
///     .use(PermissionMiddleware(delegate: myDelegate))
///     .use(RetryMiddleware(maxAttempts: 3))
///     .use(TimeoutMiddleware(duration: .seconds(30)))
///
/// let tools = pipeline.wrap(baseTools)
/// let session = AgentSession(tools: tools, ...)
/// ```
public final class ToolPipeline: @unchecked Sendable {

    private var middleware: [any ToolMiddleware] = []

    public init() {}

    /// Adds middleware to the pipeline.
    ///
    /// Middleware is executed in the order it is added.
    ///
    /// - Parameter middleware: The middleware to add.
    /// - Returns: Self for chaining.
    @discardableResult
    public func use(_ middleware: any ToolMiddleware) -> Self {
        self.middleware.append(middleware)
        return self
    }

    /// Adds multiple middleware to the pipeline.
    ///
    /// - Parameter middleware: The middleware to add.
    /// - Returns: Self for chaining.
    @discardableResult
    public func use(_ middleware: [any ToolMiddleware]) -> Self {
        self.middleware.append(contentsOf: middleware)
        return self
    }

    /// Wraps a tool with this pipeline's middleware.
    ///
    /// - Parameter tool: The tool to wrap.
    /// - Returns: A wrapped tool that executes through the pipeline.
    public func wrap<T: Tool>(_ tool: T) -> some Tool<T.Arguments, T.Output> where T.Arguments: Sendable {
        PipelinedTool(tool: tool, middleware: middleware)
    }

    /// Wraps multiple tools with this pipeline's middleware.
    ///
    /// - Parameter tools: The tools to wrap.
    /// - Returns: Wrapped tools.
    public func wrap(_ tools: [any Tool]) -> [any Tool] {
        tools.map { tool in
            AnyPipelinedTool(tool: tool, middleware: middleware)
        }
    }

    /// Executes the middleware chain.
    internal static func execute(
        context: ToolContext,
        middleware: [any ToolMiddleware],
        execute: @escaping @Sendable (ToolContext) async throws -> ToolResult
    ) async throws -> ToolResult {
        guard !middleware.isEmpty else {
            return try await execute(context)
        }

        // Build the chain from the end
        var chain: ToolMiddleware.Next = execute

        for m in middleware.reversed() {
            let currentChain = chain
            chain = { ctx in
                try await m.handle(ctx, next: currentChain)
            }
        }

        return try await chain(context)
    }
}

// MARK: - PipelinedTool

/// A tool wrapped with middleware.
public struct PipelinedTool<T: Tool>: Tool, Sendable where T.Arguments: Sendable {
    public typealias Arguments = T.Arguments
    public typealias Output = T.Output

    private let tool: T
    private let middleware: [any ToolMiddleware]

    public var name: String { tool.name }
    public var description: String { tool.description }
    public var parameters: GenerationSchema { tool.parameters }

    internal init(tool: T, middleware: [any ToolMiddleware]) {
        self.tool = tool
        self.middleware = middleware
    }

    public func call(arguments: Arguments) async throws -> Output {
        let startTime = ContinuousClock.now
        let args = arguments  // Capture for Sendable

        // Create context
        let context = ToolContext(
            toolName: name,
            arguments: String(describing: args)
        )

        // Box to capture the typed output
        let outputBox = OutputBox<Output>()

        // Execute through middleware chain
        let result = try await ToolPipeline.execute(
            context: context,
            middleware: middleware
        ) { [tool] _ in
            // Execute the actual tool (only once)
            do {
                let output = try await tool.call(arguments: args)
                outputBox.value = output  // Store the typed output
                let duration = ContinuousClock.now - startTime
                return .success(String(describing: output), duration: duration)
            } catch {
                let duration = ContinuousClock.now - startTime
                return .failure(error, duration: duration)
            }
        }

        // If middleware returned an error, throw it
        if let error = result.error {
            throw error
        }

        // Return the stored typed output
        guard let output = outputBox.value else {
            // This happens if middleware short-circuited without calling next()
            // For typed tools, this is an error since we can't produce a typed output
            throw ToolPipelineError.middlewareShortCircuited(toolName: name)
        }

        return output
    }
}

/// Box for capturing typed output in Sendable closures.
private final class OutputBox<T>: @unchecked Sendable {
    var value: T?
}

// MARK: - AnyPipelinedTool

/// Type-erased pipelined tool for heterogeneous collections.
///
/// Uses GeneratedContent as arguments and String as output, matching
/// how OpenFoundationModels handles type-erased tools internally.
internal struct AnyPipelinedTool: Tool, @unchecked Sendable {
    public typealias Arguments = GeneratedContent
    public typealias Output = String

    public let name: String
    public let description: String
    public let parameters: GenerationSchema
    public let includesSchemaInInstructions: Bool

    private let middleware: [any ToolMiddleware]
    private let executor: @Sendable (GeneratedContent) async throws -> String

    internal init(tool: any Tool, middleware: [any ToolMiddleware]) {
        self.name = tool.name
        self.description = tool.description
        self.parameters = tool.parameters
        self.includesSchemaInInstructions = tool.includesSchemaInInstructions
        self.middleware = middleware

        // Create type-erased executor using helper function
        self.executor = { [middleware] arguments in
            try await _executeWithMiddleware(
                tool: tool,
                arguments: arguments,
                middleware: middleware
            )
        }
    }

    public func call(arguments: GeneratedContent) async throws -> String {
        try await executor(arguments)
    }
}

/// Executes a type-erased tool through middleware.
private func _executeWithMiddleware(
    tool: any Tool,
    arguments: GeneratedContent,
    middleware: [any ToolMiddleware]
) async throws -> String {
    // Use generic helper to get proper typing
    return try await _executeTypedToolWithMiddleware(tool, arguments: arguments, middleware: middleware)
}

/// Generic helper for typed tool execution through middleware.
private func _executeTypedToolWithMiddleware<T: Tool>(
    _ tool: T,
    arguments: GeneratedContent,
    middleware: [any ToolMiddleware]
) async throws -> String {
    let startTime = ContinuousClock.now

    // Convert GeneratedContent to typed arguments
    let typedArgs = try T.Arguments(arguments)

    let context = ToolContext(
        toolName: tool.name,
        arguments: String(describing: typedArgs)
    )

    // Wrap tool and args for Sendable capture
    let box = ToolExecutionBox(tool: tool, arguments: typedArgs)

    // Execute through middleware chain
    let result = try await ToolPipeline.execute(
        context: context,
        middleware: middleware
    ) { _ in
        do {
            let output = try await box.execute()
            let duration = ContinuousClock.now - startTime
            return .success(output, duration: duration)
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

/// Box for capturing tool and arguments in Sendable closures.
private final class ToolExecutionBox<T: Tool>: @unchecked Sendable {
    private let tool: T
    private let arguments: T.Arguments

    init(tool: T, arguments: T.Arguments) {
        self.tool = tool
        self.arguments = arguments
    }

    func execute() async throws -> String {
        let output = try await tool.call(arguments: arguments)
        return String(describing: output.promptRepresentation)
    }
}

/// Errors from the tool pipeline.
public enum ToolPipelineError: Error, LocalizedError {
    /// Argument type mismatch during deserialization.
    case argumentTypeMismatch(expected: String, received: String)

    /// Middleware short-circuited without calling next() for a typed tool.
    ///
    /// This error occurs when middleware returns a result without executing
    /// the actual tool. For typed tools (PipelinedTool), this is an error
    /// because we cannot produce a typed output from middleware alone.
    case middlewareShortCircuited(toolName: String)

    public var errorDescription: String? {
        switch self {
        case .argumentTypeMismatch(let expected, let received):
            return "Argument type mismatch: expected \(expected), received \(received)"
        case .middlewareShortCircuited(let toolName):
            return "Middleware short-circuited without executing tool '\(toolName)'. For typed tools, all middleware must call next()."
        }
    }
}
