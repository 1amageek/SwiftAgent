//
//  GuardrailRule.swift
//  SwiftAgent
//
//  Created by SwiftAgent on 2025/01/06.
//

import Foundation

// MARK: - GuardrailRule Protocol

/// A protocol representing a single guardrail rule.
///
/// Guardrail rules define security policies that can be applied to Steps
/// in a declarative manner using the `.guardrail { }` modifier.
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
public protocol GuardrailRule: Sendable {
    /// Applies this rule to a guardrail configuration.
    ///
    /// - Parameter configuration: The configuration to modify.
    func apply(to configuration: inout GuardrailConfiguration)
}

// MARK: - Allow Rule

/// A guardrail rule that permits specific tool operations.
///
/// ## Usage
///
/// ```swift
/// .guardrail {
///     Allow(.tool("Read"))
///     Allow(.bash("git:*"))
///     Allow(.mcp("github"))
/// }
/// ```
public struct Allow: GuardrailRule {

    /// The permission rule to allow.
    public let rule: PermissionRule

    /// Creates an allow rule from a permission rule.
    ///
    /// - Parameter rule: The permission rule to allow.
    public init(_ rule: PermissionRule) {
        self.rule = rule
    }

    public func apply(to configuration: inout GuardrailConfiguration) {
        configuration.allow.append(rule)
    }
}

// MARK: - Deny Rule

/// A guardrail rule that prohibits specific tool operations.
///
/// ## Usage
///
/// ```swift
/// .guardrail {
///     Deny(.bash("rm -rf:*"))
///     Deny(.bash("sudo:*"))
///     Deny(.tool("Write"))
///
///     // Final deny - cannot be overridden by child guardrails
///     Deny.final(.bash("rm -rf /*"))
/// }
/// ```
///
/// ## Override Behavior
///
/// Regular `Deny` rules can be overridden by child guardrails using `Override`.
/// Use `Deny.final()` for security-critical restrictions that must never be relaxed.
///
/// ```swift
/// Pipeline()
///     .guardrail {
///         Deny(.bash("rm:*"))           // Can be overridden
///         Deny.final(.bash("rm -rf:*")) // Cannot be overridden
///     }
///     .body {
///         CleanupStep()
///             .guardrail {
///                 Override(.bash("rm:*.tmp"))      // ✅ Works
///                 Override(.bash("rm -rf:*"))      // ❌ Ignored (final)
///             }
///     }
/// ```
public struct Deny: GuardrailRule {

    /// The permission rule to deny.
    public let rule: PermissionRule

    /// Whether this deny rule is final (cannot be overridden).
    public let isFinal: Bool

    /// Creates a deny rule from a permission rule.
    ///
    /// - Parameter rule: The permission rule to deny.
    public init(_ rule: PermissionRule) {
        self.rule = rule
        self.isFinal = false
    }

    /// Creates a deny rule with explicit final flag.
    private init(_ rule: PermissionRule, isFinal: Bool) {
        self.rule = rule
        self.isFinal = isFinal
    }

    /// Creates a final deny rule that cannot be overridden.
    ///
    /// Use this for security-critical restrictions that child guardrails
    /// must not be able to relax.
    ///
    /// - Parameter rule: The permission rule to deny.
    /// - Returns: A final deny rule.
    public static func final(_ rule: PermissionRule) -> Deny {
        Deny(rule, isFinal: true)
    }

    public func apply(to configuration: inout GuardrailConfiguration) {
        if isFinal {
            configuration.finalDeny.append(rule)
        } else {
            configuration.deny.append(rule)
        }
    }
}

// MARK: - Override Rule

/// A guardrail rule that overrides parent deny rules.
///
/// `Override` allows child guardrails to selectively relax restrictions
/// set by parent guardrails. It only affects regular `Deny` rules, not
/// `Deny.final()` rules.
///
/// ## Usage
///
/// ```swift
/// // Parent denies all rm commands
/// Pipeline()
///     .guardrail { Deny(.bash("rm:*")) }
///     .body {
///         // Child overrides for .tmp files only
///         CleanupStep()
///             .guardrail {
///                 Override(.bash("rm:*.tmp"))
///             }
///     }
/// ```
///
/// ## Evaluation Order
///
/// ```
/// 1. Session Memory
/// 2. Final Deny (cannot be overridden)
/// 3. Override check ← if matches, skip regular deny
/// 4. Regular Deny
/// 5. Allow
/// 6. Default Action
/// ```
public struct Override: GuardrailRule {

    /// The permission rule pattern to override.
    public let rule: PermissionRule

    /// Creates an override rule.
    ///
    /// - Parameter rule: The pattern to exempt from deny rules.
    public init(_ rule: PermissionRule) {
        self.rule = rule
    }

    public func apply(to configuration: inout GuardrailConfiguration) {
        configuration.overrides.append(rule)
    }
}

// MARK: - AskUser Rule

/// A guardrail rule that requires user confirmation for tool operations.
///
/// When this rule is applied, operations that don't match Allow/Deny rules
/// will prompt the user for confirmation.
///
/// ## Usage
///
/// ```swift
/// .guardrail {
///     Allow(.tool("Read"))
///     AskUser()  // Ask for anything else
/// }
///
/// // With custom handler
/// .guardrail {
///     AskUser(handler: MyCustomHandler())
/// }
/// ```
public struct AskUser: GuardrailRule {

    /// The approval handler to use for prompts.
    public let handler: (any ApprovalHandler)?

    /// Creates an ask-user rule.
    ///
    /// - Parameter handler: Optional custom handler for user prompts.
    ///   If nil, uses the default handler from the middleware.
    public init(handler: (any ApprovalHandler)? = nil) {
        self.handler = handler
    }

    public func apply(to configuration: inout GuardrailConfiguration) {
        configuration.defaultAction = .ask
        if let handler = handler {
            configuration.handler = handler
        }
    }
}

// MARK: - Sandbox Rule

/// A guardrail rule that applies sandbox restrictions to command execution.
///
/// ## Usage
///
/// ```swift
/// .guardrail {
///     Sandbox(.restrictive)  // No network, read-only
/// }
///
/// // Or with custom configuration
/// .guardrail {
///     Sandbox(SandboxExecutor.Configuration(
///         networkPolicy: .local,
///         filePolicy: .workingDirectoryOnly,
///         allowSubprocesses: false
///     ))
/// }
/// ```
public struct Sandbox: GuardrailRule {

    /// The sandbox configuration to apply.
    public let configuration: SandboxExecutor.Configuration

    /// Creates a sandbox rule with a configuration.
    ///
    /// - Parameter configuration: The sandbox configuration.
    public init(_ configuration: SandboxExecutor.Configuration) {
        self.configuration = configuration
    }

    public func apply(to configuration: inout GuardrailConfiguration) {
        configuration.sandbox = self.configuration
    }

    // MARK: - Presets

    /// Standard sandbox: local network, working directory write.
    public static var standard: Sandbox {
        Sandbox(.standard)
    }

    /// Restrictive sandbox: no network, read-only.
    public static var restrictive: Sandbox {
        Sandbox(.restrictive)
    }

    /// Permissive sandbox: full network, working directory write.
    public static var permissive: Sandbox {
        Sandbox(.permissive)
    }
}

// MARK: - Network Control Extensions

extension Deny {

    /// Denies all network access by applying a restrictive sandbox.
    ///
    /// This is a convenience for common network restriction use cases.
    ///
    /// ## Usage
    ///
    /// ```swift
    /// .guardrail {
    ///     Deny.network
    /// }
    /// ```
    public static var network: Sandbox {
        Sandbox(SandboxExecutor.Configuration(
            networkPolicy: .none,
            filePolicy: .workingDirectoryOnly,
            allowSubprocesses: true
        ))
    }
}

extension Allow {

    /// Allows local network only (localhost, LAN).
    ///
    /// ## Usage
    ///
    /// ```swift
    /// .guardrail {
    ///     Allow.localNetwork
    /// }
    /// ```
    public static var localNetwork: Sandbox {
        Sandbox(SandboxExecutor.Configuration(
            networkPolicy: .local,
            filePolicy: .workingDirectoryOnly,
            allowSubprocesses: true
        ))
    }

    /// Allows full network access.
    ///
    /// ## Usage
    ///
    /// ```swift
    /// .guardrail {
    ///     Allow.fullNetwork
    /// }
    /// ```
    public static var fullNetwork: Sandbox {
        Sandbox(SandboxExecutor.Configuration(
            networkPolicy: .full,
            filePolicy: .workingDirectoryOnly,
            allowSubprocesses: true
        ))
    }
}
