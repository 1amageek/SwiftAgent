//
//  GuardrailContext.swift
//  SwiftAgent
//
//  Created by SwiftAgent on 2025/01/06.
//

import Foundation

/// Context key for guardrail configuration propagation via TaskLocal.
///
/// This allows `GuardedStep` to inject guardrail configuration into the
/// async call tree, and middleware to read it using `GuardrailContext.current`.
///
/// ## Design
///
/// ```
/// GuardedStep.run()
///     │
///     ├─ withContext(GuardrailContext.self, value: config)
///     │
///     └─ inner Step.run()
///           │
///           ▼
///     Tool Execution
///           │
///           ▼
///     PermissionMiddleware.handle()
///         └─ GuardrailContext.current → merge with base config
///     SandboxMiddleware.handle()
///         └─ GuardrailContext.current → override sandbox if set
/// ```
///
/// ## Usage
///
/// ```swift
/// // In GuardedStep (injection)
/// try await withContext(GuardrailContext.self, value: configuration) {
///     try await innerStep.run(input)
/// }
///
/// // In PermissionMiddleware (reading)
/// let guardrail = GuardrailContext.current
/// if !guardrail.isEmpty {
///     let effectiveConfig = guardrail.mergedPermissions(with: baseConfig)
///     // Use effectiveConfig for permission checking
/// }
/// ```
public enum GuardrailContext: ContextKey {

    /// TaskLocal storage for the current guardrail configuration.
    @TaskLocal
    private static var _current: GuardrailConfiguration?

    /// The default value when no guardrail is configured.
    public static var defaultValue: GuardrailConfiguration {
        GuardrailConfiguration()
    }

    /// The current guardrail configuration, or empty if not set.
    public static var current: GuardrailConfiguration {
        _current ?? defaultValue
    }

    /// Runs an operation with the given guardrail configuration in context.
    ///
    /// - Parameters:
    ///   - value: The guardrail configuration to make available.
    ///   - operation: The async operation to run.
    /// - Returns: The result of the operation.
    public static func withValue<T: Sendable>(
        _ value: GuardrailConfiguration,
        operation: () async throws -> T
    ) async rethrows -> T {
        try await $_current.withValue(value, operation: operation)
    }
}
