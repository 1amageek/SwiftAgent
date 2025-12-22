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
/// as well as per-tool overrides. Supports both legacy hooks and the new
/// `HookManager`/`PermissionManager` system.
///
/// ## Usage
///
/// ```swift
/// // Legacy style
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
///
/// // New style with managers
/// let hookManager = HookManager()
/// let permissionManager = PermissionManager(
///     mode: .default,
///     rules: [.allow("Read"), .deny("Bash(rm:*)")]
/// )
///
/// let options = ToolPipelineConfiguration(
///     hookManager: hookManager,
///     permissionManager: permissionManager
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

    /// Global hooks that apply to all tool executions (legacy).
    ///
    /// These are executed in addition to any tool-specific hooks.
    /// Consider using `hookManager` for more advanced hook management.
    public var globalHooks: [any ToolExecutionHook]

    /// Delegate for permission decisions (legacy).
    ///
    /// If nil, all tools are allowed.
    /// Consider using `permissionManager` for more advanced permission management.
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

    // MARK: - New Manager-Based Configuration

    /// The hook manager for advanced hook management.
    ///
    /// When set, hooks are managed through this actor instead of `globalHooks`.
    public var hookManager: HookManager?

    /// The permission manager for advanced permission checking.
    ///
    /// When set, permissions are checked through this actor instead of `permissionDelegate`.
    public var permissionManager: PermissionManager?

    /// Permission configuration for rule-based permissions.
    ///
    /// Applied to `permissionManager` if set, or creates a new manager.
    public var permissionConfiguration: PermissionConfiguration?

    /// Hook configuration for declarative hook setup.
    ///
    /// Applied to `hookManager` if set.
    public var hookConfiguration: HookConfiguration?

    /// Creates a tool pipeline configuration.
    ///
    /// - Parameters:
    ///   - defaultTimeout: Default timeout for all tools. Default is 60 seconds.
    ///   - defaultRetry: Default retry configuration. Default is nil (no retry).
    ///   - globalHooks: Hooks that apply to all tools. Default is empty.
    ///   - permissionDelegate: Permission delegate. Default is nil (allow all).
    ///   - toolOptions: Per-tool options. Default is empty.
    ///   - maxPermissionLevel: Maximum permission level allowed. Default is `.standard`.
    ///   - hookManager: Hook manager for advanced hooks. Default is nil.
    ///   - permissionManager: Permission manager for advanced permissions. Default is nil.
    ///   - permissionConfiguration: Permission configuration. Default is nil.
    ///   - hookConfiguration: Hook configuration. Default is nil.
    public init(
        defaultTimeout: Duration = .seconds(60),
        defaultRetry: RetryConfiguration? = nil,
        globalHooks: [any ToolExecutionHook] = [],
        permissionDelegate: (any ToolPermissionDelegate)? = nil,
        toolOptions: [String: ToolExecutionOptions] = [:],
        maxPermissionLevel: ToolPermissionLevel = .standard,
        hookManager: HookManager? = nil,
        permissionManager: PermissionManager? = nil,
        permissionConfiguration: PermissionConfiguration? = nil,
        hookConfiguration: HookConfiguration? = nil
    ) {
        self.defaultTimeout = defaultTimeout
        self.defaultRetry = defaultRetry
        self.globalHooks = globalHooks
        self.permissionDelegate = permissionDelegate
        self.toolOptions = toolOptions
        self.maxPermissionLevel = maxPermissionLevel
        self.hookManager = hookManager
        self.permissionManager = permissionManager
        self.permissionConfiguration = permissionConfiguration
        self.hookConfiguration = hookConfiguration
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

    /// Options for development workflows.
    ///
    /// - Allows read operations and safe build commands
    /// - Requires approval for file modifications and git operations
    public static var development: ToolPipelineConfiguration {
        ToolPipelineConfiguration(
            defaultTimeout: .seconds(120),
            permissionConfiguration: .development,
            hookConfiguration: .logging
        )
    }

    /// Options with permissive settings.
    ///
    /// - Allows most operations without confirmation
    /// - Still blocks dangerous commands like `rm -rf /`
    public static var permissive: ToolPipelineConfiguration {
        ToolPipelineConfiguration(
            defaultTimeout: .seconds(120),
            permissionConfiguration: .permissive
        )
    }

    /// Options for read-only mode.
    ///
    /// - Only allows read operations
    /// - Blocks all write operations
    public static var readOnly: ToolPipelineConfiguration {
        ToolPipelineConfiguration(
            defaultTimeout: .seconds(60),
            permissionConfiguration: .readOnly
        )
    }

    /// Creates configuration from a settings file.
    ///
    /// - Parameter path: Path to the settings file.
    /// - Returns: Configuration loaded from the file.
    public static func fromSettings(at path: String) throws -> ToolPipelineConfiguration {
        let settings = try SettingsLoader.load(from: path)
        return ToolPipelineConfiguration().with(settings: settings)
    }

    /// Creates configuration from default settings locations.
    ///
    /// Searches in:
    /// 1. Environment variable path
    /// 2. Project-level settings
    /// 3. User-level settings
    ///
    /// - Returns: Configuration loaded from settings, or default if none found.
    public static func fromDefaultSettings() throws -> ToolPipelineConfiguration {
        let settings = try SettingsLoader.loadFromDefaultLocations()
        return ToolPipelineConfiguration().with(settings: settings)
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

    /// Returns a copy with the specified hook manager.
    public func withHookManager(_ manager: HookManager) -> ToolPipelineConfiguration {
        var copy = self
        copy.hookManager = manager
        return copy
    }

    /// Returns a copy with the specified permission manager.
    public func withPermissionManager(_ manager: PermissionManager) -> ToolPipelineConfiguration {
        var copy = self
        copy.permissionManager = manager
        return copy
    }

    /// Returns a copy with the specified permission configuration.
    public func withPermissionConfiguration(_ config: PermissionConfiguration) -> ToolPipelineConfiguration {
        var copy = self
        copy.permissionConfiguration = config
        return copy
    }

    /// Returns a copy with the specified hook configuration.
    public func withHookConfiguration(_ config: HookConfiguration) -> ToolPipelineConfiguration {
        var copy = self
        copy.hookConfiguration = config
        return copy
    }

    /// Returns a copy configured from agent settings.
    public func with(settings: AgentSettings) -> ToolPipelineConfiguration {
        var copy = self
        if let permissions = settings.permissions {
            copy.permissionConfiguration = permissions
        }
        if let hooks = settings.hooks {
            copy.hookConfiguration = hooks
        }
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
