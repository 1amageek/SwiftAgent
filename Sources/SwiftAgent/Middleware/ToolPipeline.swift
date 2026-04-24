//
//  ToolPipeline.swift
//  SwiftAgent
//

import Foundation
import Synchronization

/// Deprecated compatibility wrapper for the pre-runtime middleware API.
///
/// New code should use ``ToolRuntimeConfiguration`` and ``ToolRuntime``
/// directly. This type remains to preserve source compatibility for callers
/// that still build middleware chains with `ToolPipeline`.
@available(*, deprecated, message: "Use ToolRuntimeConfiguration and ToolRuntime instead.")
public final class ToolPipeline: Sendable {
    private let configuration: Mutex<ToolRuntimeConfiguration>

    /// The middleware list retained for source compatibility.
    public var middlewareList: [any ToolMiddleware] {
        configuration.withLock { $0.middleware }
    }

    public init() {
        self.configuration = Mutex(.empty)
    }

    private init(configuration: ToolRuntimeConfiguration) {
        self.configuration = Mutex(configuration)
    }

    /// Creates a default pipeline with the standard runtime middleware.
    public static var `default`: ToolPipeline {
        ToolPipeline(configuration: .default)
    }

    /// Creates an empty pipeline with no middleware.
    public static var empty: ToolPipeline {
        ToolPipeline(configuration: .empty)
    }

    /// Adds middleware to the pipeline.
    @discardableResult
    public func use(_ middleware: any ToolMiddleware) -> Self {
        _ = configuration.withLock { config in
            config.use(middleware)
        }
        return self
    }

    /// Adds multiple middleware to the pipeline.
    @discardableResult
    public func use(_ middleware: [any ToolMiddleware]) -> Self {
        _ = configuration.withLock { config in
            config.use(middleware)
        }
        return self
    }

    /// Creates a new pipeline with dynamic permission rules.
    public func withDynamicPermissions(
        _ provider: @escaping DynamicPermissionRulesProvider
    ) -> ToolPipeline {
        let snapshot = configuration.withLock { $0 }
        return ToolPipeline(configuration: snapshot.withDynamicPermissions(provider))
    }

    /// Wraps a typed tool with this pipeline's middleware.
    public func wrap<T: Tool>(
        _ tool: T
    ) -> some Tool<T.Arguments, T.Output> where T.Arguments: Sendable, T.Output: Sendable {
        RuntimeWrappedTool(tool: tool, configuration: configuration.withLock { $0 })
    }

    /// Wraps multiple heterogeneous tools with this pipeline's middleware.
    public func wrap(_ tools: [any Tool]) -> [any Tool] {
        var config = configuration.withLock { $0 }
        config.register(tools)
        return ToolRuntime(configuration: config).publicTools()
    }
}

private struct RuntimeWrappedTool<T: Tool>: Tool, Sendable where T.Arguments: Sendable, T.Output: Sendable {
    typealias Arguments = T.Arguments
    typealias Output = T.Output

    private let tool: T
    private let runtime: ToolRuntime

    var name: String { tool.name }
    var description: String { tool.description }
    var parameters: GenerationSchema { tool.parameters }
    var includesSchemaInInstructions: Bool { tool.includesSchemaInInstructions }

    init(tool: T, configuration: ToolRuntimeConfiguration) {
        self.tool = tool
        self.runtime = ToolRuntime(configuration: configuration)
    }

    func call(arguments: T.Arguments) async throws -> T.Output {
        try await runtime.execute(tool, arguments: arguments)
    }
}
