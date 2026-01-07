//
//  GuardrailBuilder.swift
//  SwiftAgent
//
//  Created by SwiftAgent on 2025/01/06.
//

import Foundation

/// Result builder for declarative guardrail configuration.
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
/// ## Conditional Rules
///
/// ```swift
/// .guardrail {
///     Allow(.tool("Read"))
///
///     if isProduction {
///         Deny(.bash("*"))
///         Sandbox(.restrictive)
///     } else {
///         Sandbox(.permissive)
///     }
/// }
/// ```
@resultBuilder
public struct GuardrailBuilder {

    /// Builds an empty block.
    public static func buildBlock() -> [GuardrailRule] {
        []
    }

    /// Builds a block from multiple rule arrays.
    public static func buildBlock(_ components: [GuardrailRule]...) -> [GuardrailRule] {
        components.flatMap { $0 }
    }

    /// Builds an optional block.
    public static func buildOptional(_ rules: [GuardrailRule]?) -> [GuardrailRule] {
        rules ?? []
    }

    /// Builds the first branch of a conditional.
    public static func buildEither(first rules: [GuardrailRule]) -> [GuardrailRule] {
        rules
    }

    /// Builds the second branch of a conditional.
    public static func buildEither(second rules: [GuardrailRule]) -> [GuardrailRule] {
        rules
    }

    /// Builds an array of rule arrays (for loops).
    public static func buildArray(_ components: [[GuardrailRule]]) -> [GuardrailRule] {
        components.flatMap { $0 }
    }

    /// Builds a single expression from a rule.
    public static func buildExpression(_ rule: GuardrailRule) -> [GuardrailRule] {
        [rule]
    }

    /// Builds a limited availability block.
    public static func buildLimitedAvailability(_ rules: [GuardrailRule]) -> [GuardrailRule] {
        rules
    }
}
