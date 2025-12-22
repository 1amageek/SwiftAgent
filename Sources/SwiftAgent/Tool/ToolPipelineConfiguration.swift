//
//  ToolPipelineConfiguration.swift
//  SwiftAgent
//
//  Created by SwiftAgent on 2025/01/15.
//

import Foundation

/// Configuration options for the tool execution pipeline.
///
/// This struct contains global settings that apply to all tools,
/// as well as per-tool overrides.
///
/// ## Usage
///
/// ```swift
/// let options = ToolPipelineConfiguration(
///     defaultTimeout: .seconds(30),
///     defaultRetry: RetryConfiguration(maxAttempts: 2),
///     globalHooks: [LoggingToolHook()],
///     permissionDelegate: MyPermissionDelegate(),
///     toolOptions: [
///         "WriteTool": .fileModification,
///         "ExecuteCommandTool": .commandExecution
///     ]
/// )
/// ```
public struct ToolPipelineConfiguration: Sendable {

    /// Default timeout for all tool executions.
    ///
    /// Individual tools can override this with their own timeout.
    public var defaultTimeout: Duration

    /// Default retry configuration for all tools.
    ///
    /// Individual tools can override this with their own retry configuration.
    public var defaultRetry: RetryConfiguration?

    /// Global hooks that apply to all tool executions.
    ///
    /// These are executed in addition to any tool-specific hooks.
    public var globalHooks: [any ToolExecutionHook]

    /// Delegate for permission decisions.
    ///
    /// If nil, all tools are allowed.
    public var permissionDelegate: (any ToolPermissionDelegate)?

    /// Per-tool execution options.
    ///
    /// Keys are tool names, values are the options for that tool.
    public var toolOptions: [String: ToolExecutionOptions]

    /// Maximum permission level allowed for tool execution.
    ///
    /// Tools requiring a higher permission level will be rejected.
    /// Default is `.standard`.
    public var maxPermissionLevel: ToolPermissionLevel

    /// Creates a tool pipeline configuration.
    ///
    /// - Parameters:
    ///   - defaultTimeout: Default timeout for all tools. Default is 60 seconds.
    ///   - defaultRetry: Default retry configuration. Default is nil (no retry).
    ///   - globalHooks: Hooks that apply to all tools. Default is empty.
    ///   - permissionDelegate: Permission delegate. Default is nil (allow all).
    ///   - toolOptions: Per-tool options. Default is empty.
    ///   - maxPermissionLevel: Maximum permission level allowed. Default is `.standard`.
    public init(
        defaultTimeout: Duration = .seconds(60),
        defaultRetry: RetryConfiguration? = nil,
        globalHooks: [any ToolExecutionHook] = [],
        permissionDelegate: (any ToolPermissionDelegate)? = nil,
        toolOptions: [String: ToolExecutionOptions] = [:],
        maxPermissionLevel: ToolPermissionLevel = .standard
    ) {
        self.defaultTimeout = defaultTimeout
        self.defaultRetry = defaultRetry
        self.globalHooks = globalHooks
        self.permissionDelegate = permissionDelegate
        self.toolOptions = toolOptions
        self.maxPermissionLevel = maxPermissionLevel
    }

    /// Default options with no special configuration.
    public static let `default` = ToolPipelineConfiguration()

    /// Options that allow all tools with logging.
    public static func withLogging(
        logger: @escaping @Sendable (String) -> Void = { print($0) }
    ) -> ToolPipelineConfiguration {
        ToolPipelineConfiguration(
            globalHooks: [LoggingToolHook(logger: logger)]
        )
    }

    /// Options with strict security defaults.
    ///
    /// - Blocks command execution by default
    /// - Requires elevated permissions for file modifications
    public static var secure: ToolPipelineConfiguration {
        ToolPipelineConfiguration(
            defaultTimeout: .seconds(30),
            toolOptions: [
                "ExecuteCommandTool": ToolExecutionOptions(
                    requiresApproval: true,
                    permissionLevel: .dangerous
                ),
                "WriteTool": ToolExecutionOptions(
                    permissionLevel: .elevated
                ),
                "EditTool": ToolExecutionOptions(
                    permissionLevel: .elevated
                ),
                "MultiEditTool": ToolExecutionOptions(
                    permissionLevel: .elevated
                )
            ]
        )
    }

    // MARK: - Builder Methods

    /// Returns a copy with the specified timeout.
    public func withTimeout(_ timeout: Duration) -> ToolPipelineConfiguration {
        var copy = self
        copy.defaultTimeout = timeout
        return copy
    }

    /// Returns a copy with the specified retry configuration.
    public func withRetry(_ retry: RetryConfiguration?) -> ToolPipelineConfiguration {
        var copy = self
        copy.defaultRetry = retry
        return copy
    }

    /// Returns a copy with an additional global hook.
    public func withHook(_ hook: any ToolExecutionHook) -> ToolPipelineConfiguration {
        var copy = self
        copy.globalHooks.append(hook)
        return copy
    }

    /// Returns a copy with the specified permission delegate.
    public func withPermissionDelegate(_ delegate: any ToolPermissionDelegate) -> ToolPipelineConfiguration {
        var copy = self
        copy.permissionDelegate = delegate
        return copy
    }

    /// Returns a copy with options for a specific tool.
    public func withToolOptions(
        _ toolName: String,
        _ options: ToolExecutionOptions
    ) -> ToolPipelineConfiguration {
        var copy = self
        copy.toolOptions[toolName] = options
        return copy
    }

    /// Returns a copy with the specified maximum permission level.
    public func withMaxPermissionLevel(_ level: ToolPermissionLevel) -> ToolPipelineConfiguration {
        var copy = self
        copy.maxPermissionLevel = level
        return copy
    }

    // MARK: - Query Methods

    /// Gets the effective timeout for a tool.
    ///
    /// - Parameter toolName: The name of the tool.
    /// - Returns: The tool-specific timeout or the default timeout.
    public func timeout(for toolName: String) -> Duration {
        toolOptions[toolName]?.timeout ?? defaultTimeout
    }

    /// Gets the effective retry configuration for a tool.
    ///
    /// - Parameter toolName: The name of the tool.
    /// - Returns: The tool-specific retry configuration or the default.
    public func retryConfiguration(for toolName: String) -> RetryConfiguration? {
        toolOptions[toolName]?.retry ?? defaultRetry
    }

    /// Gets all hooks that apply to a tool.
    ///
    /// - Parameter toolName: The name of the tool.
    /// - Returns: Global hooks plus any tool-specific hooks.
    public func allHooks(for toolName: String) -> [any ToolExecutionHook] {
        let toolSpecificHooks = toolOptions[toolName]?.hooks ?? []
        return globalHooks + toolSpecificHooks
    }

    /// Gets the permission level for a tool.
    ///
    /// - Parameter toolName: The name of the tool.
    /// - Returns: The tool's permission level, or `.standard` if not specified.
    public func permissionLevel(for toolName: String) -> ToolPermissionLevel {
        toolOptions[toolName]?.permissionLevel ?? .standard
    }

    /// Checks if a tool requires approval.
    ///
    /// - Parameter toolName: The name of the tool.
    /// - Returns: Whether the tool requires approval.
    public func requiresApproval(for toolName: String) -> Bool {
        toolOptions[toolName]?.requiresApproval ?? false
    }
}

// MARK: - Result Builder

/// A result builder for configuring tool options.
@resultBuilder
public struct ToolOptionsBuilder {

    public static func buildBlock(_ components: (String, ToolExecutionOptions)...) -> [String: ToolExecutionOptions] {
        Dictionary(uniqueKeysWithValues: components)
    }

    public static func buildOptional(_ component: [String: ToolExecutionOptions]?) -> [String: ToolExecutionOptions] {
        component ?? [:]
    }

    public static func buildEither(first component: [String: ToolExecutionOptions]) -> [String: ToolExecutionOptions] {
        component
    }

    public static func buildEither(second component: [String: ToolExecutionOptions]) -> [String: ToolExecutionOptions] {
        component
    }
}

extension ToolPipelineConfiguration {

    /// Creates a pipeline configuration with a result builder for tool options.
    ///
    /// - Parameters:
    ///   - defaultTimeout: Default timeout.
    ///   - defaultRetry: Default retry configuration.
    ///   - globalHooks: Global hooks.
    ///   - permissionDelegate: Permission delegate.
    ///   - maxPermissionLevel: Maximum permission level allowed.
    ///   - builder: Result builder for tool options.
    public init(
        defaultTimeout: Duration = .seconds(60),
        defaultRetry: RetryConfiguration? = nil,
        globalHooks: [any ToolExecutionHook] = [],
        permissionDelegate: (any ToolPermissionDelegate)? = nil,
        maxPermissionLevel: ToolPermissionLevel = .standard,
        @ToolOptionsBuilder _ builder: () -> [String: ToolExecutionOptions]
    ) {
        self.init(
            defaultTimeout: defaultTimeout,
            defaultRetry: defaultRetry,
            globalHooks: globalHooks,
            permissionDelegate: permissionDelegate,
            toolOptions: builder(),
            maxPermissionLevel: maxPermissionLevel
        )
    }
}
