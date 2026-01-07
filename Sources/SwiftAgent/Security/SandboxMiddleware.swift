//
//  SandboxMiddleware.swift
//  SwiftAgent
//
//  Created by SwiftAgent on 2025/01/04.
//

import Foundation

/// Middleware that injects sandbox configuration via TaskLocal context.
///
/// This middleware follows the Decorator pattern - it always calls `next()`
/// and never short-circuits. It uses the `@Context` system to propagate
/// sandbox configuration to tools via TaskLocal.
///
/// ## Design
///
/// ```
/// SandboxMiddleware
///     │
///     ├─ withContext(SandboxContext.self, value: config)
///     │
///     └─ Call next(context)  ← Always calls next!
///           │
///           ▼
///     ExecuteCommandTool uses @Context
///     and executes via SandboxExecutor if not disabled
/// ```
///
/// ## Example
///
/// ```swift
/// let pipeline = ToolPipeline()
///     .use(PermissionMiddleware(configuration: .standard))
///     .use(SandboxMiddleware(configuration: .standard))
///
/// // The middleware injects config via TaskLocal, tool reads it
/// ```
public struct SandboxMiddleware: ToolMiddleware, Sendable {

    /// The sandbox configuration to inject.
    public let configuration: SandboxExecutor.Configuration

    /// Creates a sandbox middleware.
    ///
    /// - Parameter configuration: The sandbox configuration to inject.
    public init(configuration: SandboxExecutor.Configuration) {
        self.configuration = configuration
    }

    // MARK: - ToolMiddleware

    public func handle(
        _ context: ToolContext,
        next: @escaping Next
    ) async throws -> ToolResult {
        // Only inject sandbox config for Bash/ExecuteCommand tools
        guard context.toolName == "Bash" || context.toolName == "ExecuteCommand" else {
            return try await next(context)
        }

        // Get effective sandbox configuration (guardrail takes precedence)
        let effectiveSandbox = effectiveSandboxConfiguration()

        // Skip sandbox injection if effectively disabled
        guard !effectiveSandbox.isDisabled else {
            return try await next(context)
        }

        // Use the @Context system to propagate sandbox configuration via TaskLocal
        // ExecuteCommandTool reads it using @Context
        return try await withContext(SandboxContext.self, value: effectiveSandbox) {
            try await next(context)
        }
    }

    // MARK: - Guardrail Integration

    /// Gets the effective sandbox configuration, checking guardrail context first.
    ///
    /// Guardrail sandbox takes precedence over the middleware's configuration.
    private func effectiveSandboxConfiguration() -> SandboxExecutor.Configuration {
        let guardrailConfig = GuardrailContext.current
        if let guardrailSandbox = guardrailConfig.sandbox {
            return guardrailSandbox
        }
        return configuration
    }
}
