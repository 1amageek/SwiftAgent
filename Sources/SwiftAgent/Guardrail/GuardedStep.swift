//
//  GuardedStep.swift
//  SwiftAgent
//
//  Created by SwiftAgent on 2025/01/06.
//

import Foundation

/// A Step that applies guardrail rules to its execution.
///
/// `GuardedStep` wraps another Step and injects guardrail configuration
/// into the TaskLocal context during execution. This configuration is then
/// read by `PermissionMiddleware` and `SandboxMiddleware` to apply
/// security policies.
///
/// ## Design
///
/// ```
/// GuardedStep.run(input)
///     │
///     ├─ Build configuration from rules
///     ├─ Merge with parent guardrail (if nested)
///     ├─ Inject via withContext(GuardrailContext.self, ...)
///     │
///     └─ inner Step.run(input)
///           │
///           ▼
///     Tool Middleware reads GuardrailContext.current
/// ```
///
/// ## Hierarchical Guardrails
///
/// Guardrails can be nested. Inner guardrails take precedence over outer ones.
///
/// ```swift
/// Pipeline()
///     .guardrail { Sandbox(.standard) }  // Outer
///     .body {
///         Step1()
///             .guardrail { Sandbox(.restrictive) }  // Inner (wins)
///     }
/// ```
public struct GuardedStep<S: Step>: Step {
    public typealias Input = S.Input
    public typealias Output = S.Output

    private let step: S
    private let guardrail: Guardrail

    /// Creates a guarded step.
    ///
    /// - Parameters:
    ///   - step: The step to guard.
    ///   - guardrail: The guardrail to apply.
    public init(step: S, guardrail: Guardrail) {
        self.step = step
        self.guardrail = guardrail
    }

    @discardableResult
    public func run(_ input: Input) async throws -> Output {
        // Build this guardrail's configuration
        var config = guardrail.buildConfiguration()

        // Merge with parent guardrail if present (inner takes precedence)
        let parentConfig = GuardrailContext.current
        if !parentConfig.isEmpty {
            // Parent config is the base, this config overrides
            config = parentConfig.merged(with: config)
        }

        // Execute with guardrail context injected
        return try await withContext(GuardrailContext.self, value: config) {
            try await step.run(input)
        }
    }
}

// MARK: - Sendable Conformance

extension GuardedStep: Sendable where S: Sendable {}
