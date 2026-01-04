//
//  SecurityConfiguration.swift
//  SwiftAgent
//
//  Created by SwiftAgent on 2025/01/04.
//

import Foundation

/// Unified security configuration for an agent.
///
/// Combines permission checking and sandboxing into a single
/// configuration point, following the Claude Code security model.
///
/// ## Example
///
/// ```swift
/// // Standard security with CLI prompts
/// let config = AgentConfiguration(...)
///     .withSecurity(.standard.withHandler(CLIPermissionHandler()))
///
/// // Development mode (permissive)
/// let config = AgentConfiguration(...)
///     .withSecurity(.development)
///
/// // Custom security
/// let security = SecurityConfiguration(
///     permissions: PermissionConfiguration(
///         allow: [.tool("Read"), .bash("git:*")],
///         deny: [.bash("rm:*")],
///         defaultAction: .ask,
///         handler: CLIPermissionHandler()
///     ),
///     sandbox: .standard
/// )
/// ```
public struct SecurityConfiguration: Sendable {

    /// Permission configuration.
    public var permissions: PermissionConfiguration

    /// Sandbox configuration (nil = no sandbox).
    public var sandbox: SandboxExecutor.Configuration?

    /// Whether sandboxing is enabled.
    public var sandboxEnabled: Bool {
        sandbox != nil
    }

    /// Creates a security configuration.
    ///
    /// - Parameters:
    ///   - permissions: Permission configuration.
    ///   - sandbox: Sandbox configuration (nil to disable).
    public init(
        permissions: PermissionConfiguration = .standard,
        sandbox: SandboxExecutor.Configuration? = nil
    ) {
        self.permissions = permissions
        self.sandbox = sandbox
    }
}

// MARK: - Presets

extension SecurityConfiguration {

    /// Standard security: interactive permissions, standard sandbox.
    ///
    /// - Read-only tools allowed
    /// - Safe git/shell commands allowed
    /// - Dangerous commands denied
    /// - Unknown commands prompt user
    /// - Commands run in sandbox with local network only
    public static var standard: SecurityConfiguration {
        SecurityConfiguration(
            permissions: .standard,
            sandbox: .standard
        )
    }

    /// Development security: permissive permissions, no sandbox.
    ///
    /// - Most tools allowed without prompting
    /// - Only the most dangerous commands denied
    /// - No sandbox restrictions
    public static var development: SecurityConfiguration {
        SecurityConfiguration(
            permissions: .development,
            sandbox: nil
        )
    }

    /// Restrictive security: minimal permissions, restrictive sandbox.
    ///
    /// - Only read-only tools allowed
    /// - Everything else denied
    /// - Sandbox with no network and read-only filesystem
    public static var restrictive: SecurityConfiguration {
        SecurityConfiguration(
            permissions: .restrictive,
            sandbox: .restrictive
        )
    }

    /// Read-only security: no write or execute operations.
    ///
    /// - Read, Glob, Grep allowed
    /// - Write, Edit, Bash denied
    /// - No sandbox (not needed since no execution)
    public static var readOnly: SecurityConfiguration {
        SecurityConfiguration(
            permissions: .readOnly,
            sandbox: nil
        )
    }
}

// MARK: - Builder Methods

extension SecurityConfiguration {

    /// Returns a copy with a permission handler.
    ///
    /// - Parameter handler: The permission handler.
    /// - Returns: A new configuration with the handler set.
    public func withHandler(_ handler: any PermissionHandler) -> SecurityConfiguration {
        var copy = self
        copy.permissions = copy.permissions.withHandler(handler)
        return copy
    }

    /// Returns a copy with sandboxing enabled.
    ///
    /// - Parameter config: The sandbox configuration.
    /// - Returns: A new configuration with sandbox enabled.
    public func withSandbox(_ config: SandboxExecutor.Configuration) -> SecurityConfiguration {
        var copy = self
        copy.sandbox = config
        return copy
    }

    /// Returns a copy with sandboxing disabled.
    ///
    /// - Returns: A new configuration without sandbox.
    public func withoutSandbox() -> SecurityConfiguration {
        var copy = self
        copy.sandbox = nil
        return copy
    }

    /// Returns a copy with an additional allow rule.
    ///
    /// - Parameter rule: The rule to add.
    /// - Returns: A new configuration with the rule added.
    public func allowing(_ rule: PermissionRule) -> SecurityConfiguration {
        var copy = self
        copy.permissions = copy.permissions.allowing(rule)
        return copy
    }

    /// Returns a copy with an additional deny rule.
    ///
    /// - Parameter rule: The rule to add.
    /// - Returns: A new configuration with the rule added.
    public func denying(_ rule: PermissionRule) -> SecurityConfiguration {
        var copy = self
        copy.permissions = copy.permissions.denying(rule)
        return copy
    }
}

// MARK: - Public Exports

/// Re-export security types for convenience.
public typealias ToolPermissionRule = PermissionRule
public typealias ToolPermissionHandler = PermissionHandler
public typealias ToolPermissionRequest = PermissionRequest
public typealias ToolPermissionResponse = PermissionResponse
