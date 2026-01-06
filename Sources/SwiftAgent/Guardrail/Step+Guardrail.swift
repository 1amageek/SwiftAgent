//
//  Step+Guardrail.swift
//  SwiftAgent
//
//  Created by SwiftAgent on 2025/01/06.
//

import Foundation

extension Step {

    /// Applies guardrail rules to this step.
    ///
    /// Guardrails define security policies that are applied when this step
    /// (and any nested steps) execute tools.
    ///
    /// ## Usage
    ///
    /// ```swift
    /// FetchUserData()
    ///     .guardrail {
    ///         Allow(.tool("Read"))
    ///         Deny(.bash("rm:*"))
    ///         Sandbox(.restrictive)
    ///     }
    /// ```
    ///
    /// ## Hierarchical Application
    ///
    /// Guardrails can be nested. Inner guardrails take precedence over outer ones
    /// for settings like `Sandbox` and `AskUser`, while permission rules
    /// (Allow/Deny) are merged with inner rules evaluated first.
    ///
    /// ```swift
    /// Pipeline()
    ///     .guardrail { Sandbox(.standard) }  // Outer sandbox
    ///     .body {
    ///         Step1()
    ///             .guardrail { Sandbox(.restrictive) }  // Inner (wins)
    ///         Step2()  // Uses outer sandbox
    ///     }
    /// ```
    ///
    /// ## Integration with Global Security
    ///
    /// Guardrails are merged with the global security configuration set via
    /// `AgentConfiguration.withSecurity()`. Guardrail rules take precedence
    /// and are evaluated first.
    ///
    /// - Parameter rules: A builder closure that produces guardrail rules.
    /// - Returns: A step that applies the guardrail rules during execution.
    public func guardrail(
        @GuardrailBuilder _ rules: () -> [GuardrailRule]
    ) -> GuardedStep<Self> {
        GuardedStep(step: self, guardrail: Guardrail(rules: rules()))
    }

    /// Applies a preset guardrail to this step.
    ///
    /// ## Usage
    ///
    /// ```swift
    /// // Read-only access
    /// AnalyzeData()
    ///     .guardrail(.readOnly)
    ///
    /// // Standard security
    /// ProcessData()
    ///     .guardrail(.standard)
    ///
    /// // Restrictive (no network, minimal permissions)
    /// HandleSensitiveData()
    ///     .guardrail(.restrictive)
    /// ```
    ///
    /// - Parameter preset: The preset guardrail to apply.
    /// - Returns: A step that applies the guardrail during execution.
    public func guardrail(_ preset: Guardrail) -> GuardedStep<Self> {
        GuardedStep(step: self, guardrail: preset)
    }
}
