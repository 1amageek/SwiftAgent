//
//  ToolExecutionPipeline.swift
//  SwiftAgent
//
//  Created by SwiftAgent on 2025/01/15.
//

import Foundation
import OpenFoundationModels
import OpenFoundationModelsCore

/// A pipeline for executing tools with permission checks, hooks, timeout, and retry.
///
/// The pipeline processes tool execution through the following stages:
/// 1. Session Start Hooks (first tool call only)
/// 2. Permission Check - Verify the tool is allowed (can modify arguments)
/// 3. Pre-Tool Use Hooks - Run pre-execution hooks (can modify arguments)
/// 4. Execution - Run the tool with timeout and retry
/// 5. Post-Tool Use Hooks - Run post-execution hooks
///
/// ## Argument Modification
///
/// Both permission managers and hooks can modify the tool's arguments.
/// The pipeline converts arguments to JSON, allows modifications, then
/// deserializes back to typed arguments using the Tool protocol's
/// `ConvertibleFromGeneratedContent` requirement.
///
/// ## Usage
///
/// ```swift
/// // Legacy style
/// let options = ToolPipelineConfiguration(
///     defaultTimeout: .seconds(30),
///     globalHooks: [LoggingToolHook()]
/// )
///
/// let pipeline = ToolExecutionPipeline(options: options)
///
/// // New style with managers
/// let hookManager = HookManager()
/// await hookManager.register(LoggingHookHandler(), for: .preToolUse)
///
/// let permissionManager = PermissionManager(
///     mode: .default,
///     rules: [.allow("Read"), .deny("Bash(rm:*)")]
/// )
///
/// let options = ToolPipelineConfiguration(
///     hookManager: hookManager,
///     permissionManager: permissionManager
/// )
///
/// let pipeline = ToolExecutionPipeline(options: options)
/// ```
public struct ToolExecutionPipeline: Sendable {

    /// The pipeline configuration options.
    public let options: ToolPipelineConfiguration

    /// The hook manager (lazily initialized from configuration).
    private let hookManager: HookManager?

    /// The permission manager (lazily initialized from configuration).
    private let permissionManager: PermissionManager?

    /// Whether managers have been initialized.
    private let managersInitialized: Bool

    /// Creates a new tool execution pipeline.
    ///
    /// - Parameter options: Configuration options. Defaults to `.default`.
    ///
    /// - Note: If you provide `permissionConfiguration` or `hookConfiguration`
    ///   without corresponding managers, use `ToolExecutionPipeline.create(options:)`
    ///   instead to properly initialize managers with their configurations.
    public init(options: ToolPipelineConfiguration = .default) {
        self.options = options

        // Use provided managers only - don't auto-create from config
        // For config-based initialization, use the async create() factory method
        self.permissionManager = options.permissionManager
        self.hookManager = options.hookManager

        self.managersInitialized = options.permissionManager != nil || options.hookManager != nil
    }

    /// Creates a pipeline with pre-initialized managers (internal use).
    private init(
        options: ToolPipelineConfiguration,
        hookManager: HookManager?,
        permissionManager: PermissionManager?,
        managersInitialized: Bool
    ) {
        self.options = options
        self.hookManager = hookManager
        self.permissionManager = permissionManager
        self.managersInitialized = managersInitialized
    }

    /// Creates and initializes a pipeline asynchronously.
    ///
    /// This factory method creates the pipeline and applies all configurations.
    /// Use this when you have `PermissionConfiguration` or `HookConfiguration`
    /// that need to be applied to managers.
    ///
    /// ## When to Use
    ///
    /// Use this method when:
    /// - You provide `permissionConfiguration` in options
    /// - You provide `hookConfiguration` in options
    /// - You want legacy hooks to be registered with the hook manager
    ///
    /// Use `init(options:)` when:
    /// - You only use pre-configured `permissionManager` and `hookManager`
    /// - You only use legacy `permissionDelegate` and `globalHooks`
    ///
    /// - Parameter options: Configuration options.
    /// - Returns: An initialized pipeline.
    public static func create(options: ToolPipelineConfiguration = .default) async throws -> ToolExecutionPipeline {
        // Create managers if configuration is provided but manager is not
        let permissionManager: PermissionManager?
        if let config = options.permissionConfiguration {
            let manager = options.permissionManager ?? PermissionManager()
            await config.apply(to: manager)
            permissionManager = manager
        } else {
            permissionManager = options.permissionManager
        }

        let hookManager: HookManager?
        if let config = options.hookConfiguration {
            let manager = options.hookManager ?? HookManager()
            let factory = DefaultHookHandlerFactory()
            try await config.apply(to: manager, handlerFactory: factory)
            hookManager = manager
        } else {
            hookManager = options.hookManager
        }

        // Register legacy hooks with hook manager if both are present
        if let manager = hookManager, !options.globalHooks.isEmpty {
            for legacyHook in options.globalHooks {
                await manager.register(legacyHook: legacyHook)
            }
        }

        return ToolExecutionPipeline(
            options: options,
            hookManager: hookManager,
            permissionManager: permissionManager,
            managersInitialized: true
        )
    }

    /// Initializes managers from configuration asynchronously.
    ///
    /// - Note: Prefer using `ToolExecutionPipeline.create(options:)` instead.
    ///   This method exists for backward compatibility.
    @available(*, deprecated, message: "Use ToolExecutionPipeline.create(options:) instead")
    public func initializeManagers() async throws {
        // Apply permission configuration if provided
        if let permissionConfig = options.permissionConfiguration,
           let manager = permissionManager {
            await permissionConfig.apply(to: manager)
        }

        // Apply hook configuration if provided
        if let hookConfig = options.hookConfiguration,
           let manager = hookManager {
            let factory = DefaultHookHandlerFactory()
            try await hookConfig.apply(to: manager, handlerFactory: factory)
        }

        // Register legacy hooks with hook manager if both are present
        if let manager = hookManager, !options.globalHooks.isEmpty {
            for legacyHook in options.globalHooks {
                await manager.register(legacyHook: legacyHook)
            }
        }
    }

    /// Executes a tool through the pipeline.
    ///
    /// - Parameters:
    ///   - tool: The tool to execute.
    ///   - arguments: The arguments for the tool.
    ///   - context: The execution context.
    /// - Returns: The tool's output.
    /// - Throws: `ToolExecutionError` or any error from the tool itself.
    public func execute<T: Tool>(
        tool: T,
        arguments: T.Arguments,
        context: ToolExecutionContext
    ) async throws -> T.Output {
        let toolName = tool.name

        // Get tool-specific options
        let toolOptions = options.toolOptions[toolName] ?? .default

        // Phase 1: Check approval requirement (legacy)
        if toolOptions.requiresApproval {
            throw ToolExecutionError.approvalRequired(toolName: toolName)
        }

        // Phase 2: Check permission level (legacy)
        if toolOptions.permissionLevel > context.permissionLevel {
            throw ToolExecutionError.permissionDenied(
                toolName: toolName,
                reason: "Tool '\(toolName)' requires \(toolOptions.permissionLevel.description) permission, but session only allows \(context.permissionLevel.description)"
            )
        }

        // Phase 3: Serialize arguments to JSON for permission/hook inspection
        var currentJSON = serializeArguments(arguments)
        var argumentsModified = false

        // Phase 4: Permission Check (new manager or legacy delegate)
        let permissionResult = try await checkPermissionWithManager(
            toolName: toolName,
            arguments: currentJSON,
            context: context
        )

        if case .allowedWithModifiedInput(let newJSON) = permissionResult {
            currentJSON = newJSON
            argumentsModified = true
        }

        // Phase 5: Pre-Tool Use Hooks (new manager or legacy hooks)
        let preHookResult = try await runPreToolUseHooks(
            toolName: toolName,
            arguments: currentJSON,
            context: context
        )

        if let modifiedJSON = preHookResult.modifiedInput {
            currentJSON = modifiedJSON
            argumentsModified = true
        }

        // Phase 6: Deserialize arguments if modified
        let finalArguments: T.Arguments
        if argumentsModified {
            do {
                let content = try GeneratedContent(json: currentJSON)
                finalArguments = try T.Arguments(content)
            } catch {
                throw ToolExecutionError.argumentParseFailed(
                    toolName: toolName,
                    json: currentJSON,
                    underlyingError: error
                )
            }
        } else {
            finalArguments = arguments
        }

        // Phase 7: Execute with Retry
        let startTime = ContinuousClock.now
        let output: T.Output

        do {
            output = try await executeWithRetry(
                tool: tool,
                arguments: finalArguments,
                context: context,
                toolOptions: toolOptions
            )
        } catch {
            // Phase 8: Error Hooks (legacy only for now)
            let allHooks = options.allHooks(for: toolName)
            let recovery = try await runErrorHooks(
                hooks: allHooks,
                toolName: toolName,
                arguments: currentJSON,
                error: error,
                context: context
            )

            switch recovery {
            case .rethrow:
                throw error

            case .retry(let delay):
                try await Task.sleep(for: delay)
                return try await execute(tool: tool, arguments: arguments, context: context)

            case .fallback(let fallbackOutput):
                // Throw special error to be caught by wrapper
                throw ToolExecutionError.fallbackRequested(output: fallbackOutput)
            }
        }

        let duration = ContinuousClock.now - startTime

        // Phase 9: Post-Tool Use Hooks (new manager or legacy hooks)
        let outputString = String(describing: output)
        try await runPostToolUseHooks(
            toolName: toolName,
            arguments: currentJSON,
            output: outputString,
            duration: duration,
            context: context
        )

        return output
    }

    // MARK: - Argument Serialization

    /// Serializes arguments to JSON string.
    ///
    /// If the arguments conform to `ConvertibleToGeneratedContent`, uses the
    /// `generatedContent.jsonString` for proper JSON serialization.
    /// Otherwise, falls back to `String(describing:)`.
    private func serializeArguments<A>(_ arguments: A) -> String {
        if let convertible = arguments as? any ConvertibleToGeneratedContent {
            return convertible.generatedContent.jsonString
        }
        // Fallback for types not conforming to ConvertibleToGeneratedContent
        return String(describing: arguments)
    }

    // MARK: - Permission Check (New Manager-Based)

    /// Checks permission using the permission manager or legacy delegate.
    ///
    /// - Returns: The permission check result.
    private func checkPermissionWithManager(
        toolName: String,
        arguments: String,
        context: ToolExecutionContext
    ) async throws -> PermissionCheckResult {
        // Use permission manager if available
        if let manager = permissionManager {
            let permissionContext = ToolPermissionContext(
                sessionID: context.sessionID,
                turnNumber: context.turnNumber,
                previousToolCalls: context.previousToolCalls
            )

            let result = try await manager.checkPermission(
                toolName: toolName,
                arguments: arguments,
                context: permissionContext
            )

            switch result {
            case .allowed, .allowedWithModifiedInput:
                return result

            case .denied(let reason):
                throw ToolExecutionError.permissionDenied(
                    toolName: toolName,
                    reason: reason
                )

            case .askRequired:
                throw ToolExecutionError.approvalRequired(toolName: toolName)
            }
        }

        // Fall back to legacy delegate
        guard let permissionDelegate = options.permissionDelegate else {
            return .allowed // No delegate means allow all
        }

        let permissionContext = ToolPermissionContext(
            sessionID: context.sessionID,
            turnNumber: context.turnNumber,
            previousToolCalls: context.previousToolCalls
        )

        let result = try await permissionDelegate.canUseTool(
            named: toolName,
            arguments: arguments,
            context: permissionContext
        )

        switch result {
        case .allow:
            return .allowed
        case .allowWithModifiedInput(let modified):
            return .allowedWithModifiedInput(modified)
        case .deny(let reason):
            throw ToolExecutionError.permissionDenied(
                toolName: toolName,
                reason: reason
            )
        case .denyAndInterrupt(let reason):
            throw ToolExecutionError.executionInterrupted(
                toolName: toolName,
                reason: reason
            )
        }
    }

    // MARK: - Hooks (New Manager-Based)

    /// Runs pre-tool use hooks using the hook manager or legacy hooks.
    ///
    /// - Returns: The aggregated hook result.
    private func runPreToolUseHooks(
        toolName: String,
        arguments: String,
        context: ToolExecutionContext
    ) async throws -> AggregatedHookResult {
        // Use hook manager if available
        if let manager = hookManager {
            let hookContext = HookContext.preToolUse(
                toolName: toolName,
                toolInput: arguments,
                toolUseID: context.toolCallID,
                sessionID: context.sessionID,
                traceID: context.traceID
            )

            let result = try await manager.execute(event: .preToolUse, context: hookContext)

            // Handle blocking results
            if !result.decision.allowsExecution {
                switch result.decision {
                case .block(let reason), .deny(let reason):
                    throw ToolExecutionError.blockedByHook(
                        toolName: toolName,
                        reason: reason
                    )
                case .ask:
                    throw ToolExecutionError.approvalRequired(toolName: toolName)
                case .stop(let reason, _):
                    throw PermissionError.agentStopped(reason: reason)
                default:
                    break
                }
            }

            return result
        }

        // Fall back to legacy hooks
        let allHooks = options.allHooks(for: toolName)
        let legacyResult = try await runBeforeHooks(
            hooks: allHooks,
            toolName: toolName,
            arguments: arguments,
            context: context
        )

        return AggregatedHookResult(
            decision: .continue,
            modifiedInput: legacyResult.modifiedArguments
        )
    }

    /// Runs post-tool use hooks using the hook manager or legacy hooks.
    private func runPostToolUseHooks(
        toolName: String,
        arguments: String,
        output: String,
        duration: Duration,
        context: ToolExecutionContext
    ) async throws {
        // Use hook manager if available
        if let manager = hookManager {
            let hookContext = HookContext.postToolUse(
                toolName: toolName,
                toolInput: arguments,
                toolOutput: output,
                executionDuration: duration,
                toolUseID: context.toolCallID,
                sessionID: context.sessionID,
                traceID: context.traceID
            )

            _ = try await manager.execute(event: .postToolUse, context: hookContext)
            return
        }

        // Fall back to legacy hooks
        let allHooks = options.allHooks(for: toolName)
        try await runAfterHooks(
            hooks: allHooks,
            toolName: toolName,
            arguments: arguments,
            output: output,
            duration: duration,
            context: context
        )
    }

    // MARK: - Legacy Hook Methods

    /// Result of running before hooks.
    private struct BeforeHooksResult {
        /// The final arguments JSON after all hooks have run.
        /// `nil` if no hooks modified the arguments.
        let modifiedArguments: String?
    }

    /// Runs before hooks and collects any argument modifications.
    ///
    /// - Returns: Result containing modified arguments if any hook modified them.
    private func runBeforeHooks(
        hooks: [any ToolExecutionHook],
        toolName: String,
        arguments: String,
        context: ToolExecutionContext
    ) async throws -> BeforeHooksResult {
        var currentArguments = arguments
        var wasModified = false

        for hook in hooks {
            let decision = try await hook.beforeExecution(
                toolName: toolName,
                arguments: currentArguments,
                context: context
            )

            switch decision {
            case .proceed:
                continue

            case .proceedWithModifiedArgs(let newArgs):
                currentArguments = newArgs
                wasModified = true

            case .block(let reason):
                throw ToolExecutionError.blockedByHook(
                    toolName: toolName,
                    reason: reason
                )

            case .requireApproval:
                throw ToolExecutionError.approvalRequired(toolName: toolName)
            }
        }

        return BeforeHooksResult(
            modifiedArguments: wasModified ? currentArguments : nil
        )
    }

    private func runAfterHooks(
        hooks: [any ToolExecutionHook],
        toolName: String,
        arguments: String,
        output: String,
        duration: Duration,
        context: ToolExecutionContext
    ) async throws {
        for hook in hooks {
            try await hook.afterExecution(
                toolName: toolName,
                arguments: arguments,
                output: output,
                duration: duration,
                context: context
            )
        }
    }

    private func runErrorHooks(
        hooks: [any ToolExecutionHook],
        toolName: String,
        arguments: String,
        error: Error,
        context: ToolExecutionContext
    ) async throws -> ToolErrorRecovery {
        var lastRecovery: ToolErrorRecovery = .rethrow

        for hook in hooks {
            lastRecovery = try await hook.onError(
                toolName: toolName,
                arguments: arguments,
                error: error,
                context: context
            )

            // If any hook suggests retry or fallback, use that
            switch lastRecovery {
            case .retry, .fallback:
                return lastRecovery
            case .rethrow:
                continue
            }
        }

        return lastRecovery
    }

    // MARK: - Execution with Retry

    private func executeWithRetry<T: Tool>(
        tool: T,
        arguments: T.Arguments,
        context: ToolExecutionContext,
        toolOptions: ToolExecutionOptions
    ) async throws -> T.Output {
        let retryConfig = toolOptions.retry ?? options.defaultRetry
        let maxAttempts = retryConfig?.maxAttempts ?? 1

        var lastError: Error?

        for attempt in 1...maxAttempts {
            do {
                // Execute the tool directly
                // Note: Timeout is enforced at the wrapper level (PipelineWrappedTool)
                // where the output type is String (Sendable), allowing safe task group usage.
                return try await tool.call(arguments: arguments)
            } catch {
                lastError = error

                // Check if we should retry
                if let retryConfig = retryConfig,
                   attempt < maxAttempts {
                    let shouldRetry = retryConfig.shouldRetry?(error) ?? true

                    if shouldRetry {
                        let delay = retryConfig.strategy.delay(
                            for: attempt,
                            baseDelay: retryConfig.baseDelay
                        )
                        try await Task.sleep(for: delay)
                        continue
                    }
                }

                throw error
            }
        }

        throw lastError ?? ToolExecutionError.unknown
    }
}

// MARK: - Convenience Factory Methods

extension ToolExecutionPipeline {

    /// Creates a pipeline with logging enabled.
    public static func withLogging(
        logger: @escaping @Sendable (String) -> Void = { print($0) }
    ) -> ToolExecutionPipeline {
        ToolExecutionPipeline(options: .withLogging(logger: logger))
    }

    /// Creates a pipeline with secure defaults.
    public static var secure: ToolExecutionPipeline {
        ToolExecutionPipeline(options: .secure)
    }
}
