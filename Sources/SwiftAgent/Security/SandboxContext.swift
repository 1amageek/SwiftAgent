//
//  SandboxContext.swift
//  SwiftAgent
//
//  Created by SwiftAgent on 2025/01/04.
//

import Foundation

/// Context key for sandbox configuration propagation via TaskLocal.
///
/// This allows `SandboxMiddleware` to inject sandbox configuration into the
/// async call tree, and `ExecuteCommandTool` to read it using `@OptionalContext`.
///
/// ## Usage
///
/// ```swift
/// // In middleware
/// try await withContext(SandboxContext.self, value: configuration) {
///     try await next(context)
/// }
///
/// // In tool
/// struct ExecuteCommandTool: Tool {
///     @OptionalContext(SandboxContext.self) var sandboxConfig: SandboxExecutor.Configuration?
///
///     func call(arguments: Args) async throws -> Output {
///         if let config = sandboxConfig {
///             // Execute in sandbox
///         }
///     }
/// }
/// ```
public enum SandboxContext: ContextKey {
    @TaskLocal
    public static var current: SandboxExecutor.Configuration?

    public static func withValue<T: Sendable>(
        _ value: SandboxExecutor.Configuration,
        operation: () async throws -> T
    ) async rethrows -> T {
        try await $current.withValue(value, operation: operation)
    }
}
