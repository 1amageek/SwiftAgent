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
/// async call tree, and `ExecuteCommandTool` to read it using `@Context`.
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
///     @Context(SandboxContext.self) var sandboxConfig: SandboxExecutor.Configuration
///
///     func call(arguments: Args) async throws -> Output {
///         if !sandboxConfig.isDisabled {
///             // Execute in sandbox
///         }
///     }
/// }
/// ```
public enum SandboxContext: ContextKey {
    @TaskLocal
    private static var _current: SandboxExecutor.Configuration?

    public static var defaultValue: SandboxExecutor.Configuration {
        .none
    }

    public static var current: SandboxExecutor.Configuration {
        _current ?? defaultValue
    }

    public static func withValue<T: Sendable>(
        _ value: SandboxExecutor.Configuration,
        operation: () async throws -> T
    ) async rethrows -> T {
        try await $_current.withValue(value, operation: operation)
    }
}
