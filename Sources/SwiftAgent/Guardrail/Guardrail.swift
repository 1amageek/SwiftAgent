//
//  Guardrail.swift
//  SwiftAgent
//
//  Created by SwiftAgent on 2025/01/06.
//

import Foundation

/// A collection of guardrail rules that form a security policy.
///
/// `Guardrail` provides a way to define security policies that can be
/// applied to Steps using the `.guardrail()` modifier.
///
/// ## Usage
///
/// ```swift
/// // Using builder syntax
/// FetchUserData()
///     .guardrail {
///         Allow(.tool("Read"))
///         Deny(.bash("rm:*"))
///     }
///
/// // Using preset
/// ProcessData()
///     .guardrail(.readOnly)
/// ```
public struct Guardrail: Sendable {

    /// The rules that define this guardrail.
    public let rules: [GuardrailRule]

    /// Creates a guardrail from rules built with the result builder.
    ///
    /// - Parameter builder: A builder closure that produces rules.
    public init(@GuardrailBuilder _ builder: () -> [GuardrailRule]) {
        self.rules = builder()
    }

    /// Creates a guardrail from an array of rules.
    ///
    /// - Parameter rules: The rules to include.
    public init(rules: [GuardrailRule]) {
        self.rules = rules
    }

    /// Builds the guardrail configuration from rules.
    ///
    /// - Returns: A configuration with all rules applied.
    public func buildConfiguration() -> GuardrailConfiguration {
        GuardrailConfiguration.build(from: rules)
    }
}

// MARK: - Presets

extension Guardrail {

    /// Read-only guardrail: allows reads, denies writes and execution.
    ///
    /// Use this for Steps that should only observe data without modifying it.
    ///
    /// ## Allowed
    /// - Read, Glob, Grep
    ///
    /// ## Denied
    /// - Write, Edit, MultiEdit, Bash
    public static var readOnly: Guardrail {
        Guardrail {
            Allow(.tool("Read"))
            Allow(.tool("Glob"))
            Allow(.tool("Grep"))
            Deny(.tool("Write"))
            Deny(.tool("Edit"))
            Deny(.tool("MultiEdit"))
            Deny(.tool("Bash"))
        }
    }

    /// Standard guardrail: sensible defaults with user prompts.
    ///
    /// - Safe read operations allowed
    /// - Safe git commands allowed
    /// - Dangerous commands denied
    /// - Unknown operations prompt user
    /// - Standard sandbox enabled
    public static var standard: Guardrail {
        Guardrail {
            // Read-only tools
            Allow(.tool("Read"))
            Allow(.tool("Glob"))
            Allow(.tool("Grep"))

            // Safe git commands
            Allow(.bash("git status"))
            Allow(.bash("git log:*"))
            Allow(.bash("git diff:*"))
            Allow(.bash("git branch:*"))

            // Dangerous commands denied
            Deny(.bash("rm -rf:*"))
            Deny(.bash("rm -fr:*"))
            Deny(.bash("sudo:*"))

            // Unknown operations prompt user
            AskUser()

            // Standard sandbox
            Sandbox.standard
        }
    }

    /// Restrictive guardrail: minimal permissions with strict sandbox.
    ///
    /// Use this for Steps that handle sensitive data or untrusted input.
    ///
    /// - Only read operations allowed
    /// - All other operations denied (no prompts)
    /// - Restrictive sandbox (no network, read-only filesystem)
    public static var restrictive: Guardrail {
        Guardrail {
            Allow(.tool("Read"))
            Allow(.tool("Glob"))
            Allow(.tool("Grep"))
            Sandbox.restrictive
        }
    }

    /// Network-restricted guardrail: denies all network access.
    ///
    /// Use this for Steps that should not make network requests.
    public static var noNetwork: Guardrail {
        Guardrail {
            Deny.network
        }
    }
}
