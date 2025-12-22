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
/// 1. Permission Check - Verify the tool is allowed (can modify arguments)
/// 2. Before Hooks - Run pre-execution hooks (can modify arguments)
/// 3. Execution - Run the tool with timeout and retry
/// 4. After Hooks - Run post-execution hooks
///
/// ## Argument Modification
///
/// Both permission delegates and hooks can modify the tool's arguments.
/// The pipeline converts arguments to JSON, allows modifications, then
/// deserializes back to typed arguments using the Tool protocol's
/// `ConvertibleFromGeneratedContent` requirement.
///
/// ## Usage
///
/// ```swift
/// let options = ToolPipelineConfiguration(
///     defaultTimeout: .seconds(30),
///     globalHooks: [LoggingToolHook()]
/// )
///
/// let pipeline = ToolExecutionPipeline(options: options)
///
/// let context = ToolExecutionContext.fromSession(
///     sessionID: "session-1",
///     turnNumber: 1
/// )
///
/// let result = try await pipeline.execute(
///     tool: myTool,
///     arguments: args,
///     context: context
/// )
/// ```
public struct ToolExecutionPipeline: Sendable {

    /// The pipeline configuration options.
    public let options: ToolPipelineConfiguration

    /// Creates a new tool execution pipeline.
    ///
    /// - Parameter options: Configuration options. Defaults to `.default`.
    public init(options: ToolPipelineConfiguration = .default) {
        self.options = options
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

        // Phase 1: Check approval requirement
        if toolOptions.requiresApproval {
            throw ToolExecutionError.approvalRequired(toolName: toolName)
        }

        // Phase 2: Check permission level
        if toolOptions.permissionLevel > context.permissionLevel {
            throw ToolExecutionError.permissionDenied(
                toolName: toolName,
                reason: "Tool '\(toolName)' requires \(toolOptions.permissionLevel.description) permission, but session only allows \(context.permissionLevel.description)"
            )
        }

        // Phase 3: Serialize arguments to JSON for permission/hook inspection
        var currentJSON = serializeArguments(arguments)
        var argumentsModified = false

        // Phase 4: Permission Delegate Check (can modify arguments)
        let permissionResult = try await checkPermission(
            toolName: toolName,
            arguments: currentJSON,
            context: context
        )

        if case .allowWithModifiedInput(let newJSON) = permissionResult {
            currentJSON = newJSON
            argumentsModified = true
        }

        // Phase 5: Before Hooks (can modify arguments)
        let allHooks = options.allHooks(for: toolName)
        let hookResult = try await runBeforeHooks(
            hooks: allHooks,
            toolName: toolName,
            arguments: currentJSON,
            context: context
        )

        if let modifiedJSON = hookResult.modifiedArguments {
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
            // Phase 8: Error Hooks
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

        // Phase 9: After Hooks
        let outputString = String(describing: output)
        try await runAfterHooks(
            hooks: allHooks,
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

    // MARK: - Permission Check

    /// Checks permission and returns the result.
    ///
    /// - Returns: The permission result, which may include modified arguments.
    private func checkPermission(
        toolName: String,
        arguments: String,
        context: ToolExecutionContext
    ) async throws -> ToolPermissionResult {
        guard let permissionDelegate = options.permissionDelegate else {
            return .allow // No delegate means allow all
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
        case .allow, .allowWithModifiedInput:
            return result

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

    // MARK: - Hooks

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
