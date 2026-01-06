//
//  GuardrailConfiguration.swift
//  SwiftAgent
//
//  Created by SwiftAgent on 2025/01/06.
//

import Foundation

/// Configuration assembled from guardrail rules.
///
/// This type holds the security policies that can be applied at the Step level.
/// It is designed to be merged with global `SecurityConfiguration` at runtime.
///
/// ## Relationship to SecurityConfiguration
///
/// `GuardrailConfiguration` is a Step-level overlay on top of the global
/// `SecurityConfiguration` set via `AgentConfiguration.withSecurity()`.
///
/// ```
/// Global (AgentConfiguration.withSecurity())
///     │
///     ├── PermissionConfiguration (allow/deny/handler)
///     └── SandboxExecutor.Configuration
///
/// Step-level (.guardrail { })
///     │
///     └── GuardrailConfiguration ← merged at runtime
/// ```
///
/// ## Merge Behavior
///
/// When a Step with guardrails executes, the guardrail configuration is merged
/// with the global configuration:
///
/// - **allow/deny**: Guardrail rules are prepended (evaluated first)
/// - **defaultAction**: Guardrail overrides if set
/// - **handler**: Guardrail overrides if set
/// - **sandbox**: Guardrail overrides if set
public struct GuardrailConfiguration: Sendable {

    /// Allowed patterns (prepended to global allow rules).
    public var allow: [PermissionRule]

    /// Denied patterns (prepended to global deny rules).
    /// These can be overridden by child guardrails using `Override`.
    public var deny: [PermissionRule]

    /// Final deny patterns that cannot be overridden.
    ///
    /// These are absolute restrictions that child guardrails cannot relax.
    /// Use for security-critical policies.
    ///
    /// ```swift
    /// .guardrail {
    ///     Deny.final(.bash("rm -rf:*"))  // Cannot be overridden
    /// }
    /// ```
    public var finalDeny: [PermissionRule]

    /// Override patterns that exempt from parent deny rules.
    ///
    /// When a context matches an override pattern, it bypasses regular deny
    /// checks (but NOT finalDeny). This allows child guardrails to selectively
    /// relax parent restrictions.
    ///
    /// ```swift
    /// .guardrail {
    ///     Override(.bash("rm:*.tmp"))  // Allows rm for .tmp files
    /// }
    /// ```
    public var overrides: [PermissionRule]

    /// Default action when no rule matches.
    /// `nil` means use the global configuration's default action.
    public var defaultAction: PermissionDecision?

    /// Handler for "ask" decisions.
    /// `nil` means use the global configuration's handler.
    public var handler: (any PermissionHandler)?

    /// Sandbox configuration.
    /// `nil` means use the global configuration's sandbox (or none).
    public var sandbox: SandboxExecutor.Configuration?

    /// Creates an empty guardrail configuration.
    public init() {
        self.allow = []
        self.deny = []
        self.finalDeny = []
        self.overrides = []
        self.defaultAction = nil
        self.handler = nil
        self.sandbox = nil
    }

    /// Creates a guardrail configuration with specified values.
    public init(
        allow: [PermissionRule] = [],
        deny: [PermissionRule] = [],
        finalDeny: [PermissionRule] = [],
        overrides: [PermissionRule] = [],
        defaultAction: PermissionDecision? = nil,
        handler: (any PermissionHandler)? = nil,
        sandbox: SandboxExecutor.Configuration? = nil
    ) {
        self.allow = allow
        self.deny = deny
        self.finalDeny = finalDeny
        self.overrides = overrides
        self.defaultAction = defaultAction
        self.handler = handler
        self.sandbox = sandbox
    }
}

// MARK: - Merging

extension GuardrailConfiguration {

    /// Merges this guardrail configuration with a permission configuration.
    ///
    /// Guardrail rules take precedence (evaluated first).
    ///
    /// - Parameter base: The base permission configuration.
    /// - Returns: A new permission configuration with guardrail rules applied.
    public func mergedPermissions(with base: PermissionConfiguration) -> PermissionConfiguration {
        PermissionConfiguration(
            // Guardrail rules are prepended (evaluated first)
            allow: allow + base.allow,
            deny: deny + base.deny,
            finalDeny: finalDeny + base.finalDeny,
            overrides: overrides + base.overrides,
            // Guardrail overrides if set
            defaultAction: defaultAction ?? base.defaultAction,
            handler: handler ?? base.handler,
            enableSessionMemory: base.enableSessionMemory
        )
    }

    /// Merges this guardrail configuration with a sandbox configuration.
    ///
    /// Guardrail sandbox takes precedence if set.
    ///
    /// - Parameter base: The base sandbox configuration (may be nil).
    /// - Returns: The effective sandbox configuration.
    public func mergedSandbox(with base: SandboxExecutor.Configuration?) -> SandboxExecutor.Configuration? {
        // Guardrail sandbox takes precedence if set
        sandbox ?? base
    }

    /// Merges another guardrail configuration into this one.
    ///
    /// The `other` configuration (inner guardrail) takes precedence.
    /// This is used for hierarchical guardrails where inner takes priority.
    ///
    /// ## Merge Rules
    ///
    /// - **finalDeny**: Inner rules prepended (all accumulated, cannot be overridden)
    /// - **overrides**: Inner overrides are prepended (evaluated first)
    /// - **deny**: Inner deny rules are prepended
    /// - **allow**: Inner allow rules are prepended
    /// - **sandbox/handler/defaultAction**: Inner overrides if set
    ///
    /// - Parameter other: The configuration to merge (inner/child guardrail).
    /// - Returns: A merged configuration.
    public func merged(with other: GuardrailConfiguration) -> GuardrailConfiguration {
        GuardrailConfiguration(
            // Inner (other) rules are prepended to be evaluated first
            allow: other.allow + allow,
            deny: other.deny + deny,
            // FinalDeny: inner first for consistency (all are checked regardless)
            finalDeny: other.finalDeny + finalDeny,
            // Inner overrides are prepended
            overrides: other.overrides + overrides,
            // Inner (other) overrides if set
            defaultAction: other.defaultAction ?? defaultAction,
            handler: other.handler ?? handler,
            sandbox: other.sandbox ?? sandbox
        )
    }
}

// MARK: - Building from Rules

extension GuardrailConfiguration {

    /// Builds a configuration from an array of guardrail rules.
    ///
    /// - Parameter rules: The rules to apply.
    /// - Returns: A configuration with all rules applied.
    public static func build(from rules: [GuardrailRule]) -> GuardrailConfiguration {
        var config = GuardrailConfiguration()
        for rule in rules {
            rule.apply(to: &config)
        }
        return config
    }
}

// MARK: - Convenience Checks

extension GuardrailConfiguration {

    /// Returns `true` if this configuration has any permission rules.
    public var hasPermissionRules: Bool {
        !allow.isEmpty || !deny.isEmpty || !finalDeny.isEmpty || !overrides.isEmpty || defaultAction != nil || handler != nil
    }

    /// Returns `true` if this configuration has a sandbox configuration.
    public var hasSandbox: Bool {
        sandbox != nil
    }

    /// Returns `true` if this configuration is empty (no rules or settings).
    public var isEmpty: Bool {
        !hasPermissionRules && !hasSandbox
    }
}
