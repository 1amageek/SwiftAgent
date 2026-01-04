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
///     ExecuteCommandTool uses @OptionalContext(SandboxContext.self)
///     and executes via SandboxExecutor
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

        // Use the @Context system to propagate sandbox configuration via TaskLocal
        // ExecuteCommandTool can read it using @OptionalContext(SandboxContext.self)
        return try await withContext(SandboxContext.self, value: configuration) {
            try await next(context)
        }
    }
}
