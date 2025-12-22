//
//  PermissionConfiguration.swift
//  SwiftAgent
//
//  Created by SwiftAgent on 2025/01/23.
//

import Foundation

/// Configuration for permission rules and settings.
///
/// `PermissionConfiguration` defines the permission rules that control
/// what tools can be used and under what conditions.
///
/// ## Configuration File Format
///
/// Permissions can be defined in a JSON settings file:
///
/// ```json
/// {
///   "permissions": {
///     "defaultMode": "default",
///     "allow": [
///       "Read",
///       "Glob",
///       "Grep",
///       "WebFetch(domain:github.com)"
///     ],
///     "deny": [
///       "Bash(rm -rf:*)",
///       "Edit(.env)"
///     ],
///     "ask": [
///       "Edit(/src/**)",
///       "Bash(git push:*)"
///     ]
///   }
/// }
/// ```
public struct PermissionConfiguration: Codable, Sendable {

    /// The default permission mode.
    public var defaultMode: PermissionMode

    /// List of allow rule patterns.
    public var allow: [String]

    /// List of deny rule patterns.
    public var deny: [String]

    /// List of ask rule patterns.
    public var ask: [String]

    /// Maximum tool permission level allowed.
    public var maxLevel: ToolPermissionLevel?

    /// Tool-specific permission level overrides.
    public var toolLevels: [String: ToolPermissionLevel]?

    /// Creates a permission configuration.
    public init(
        defaultMode: PermissionMode = .default,
        allow: [String] = [],
        deny: [String] = [],
        ask: [String] = [],
        maxLevel: ToolPermissionLevel? = nil,
        toolLevels: [String: ToolPermissionLevel]? = nil
    ) {
        self.defaultMode = defaultMode
        self.allow = allow
        self.deny = deny
        self.ask = ask
        self.maxLevel = maxLevel
        self.toolLevels = toolLevels
    }

    /// Converts to permission rules.
    public func toRules() -> [PermissionRule] {
        var rules: [PermissionRule] = []

        for pattern in allow {
            rules.append(.allow(pattern))
        }

        for pattern in deny {
            rules.append(.deny(pattern))
        }

        for pattern in ask {
            rules.append(.ask(pattern))
        }

        return rules
    }

    /// Applies this configuration to a permission manager.
    public func apply(to manager: PermissionManager) async {
        await manager.setMode(defaultMode)
        await manager.clearRules()
        await manager.addRules(toRules())

        if let maxLevel = maxLevel {
            await manager.setMaxLevel(maxLevel)
        }

        if let toolLevels = toolLevels {
            await manager.setToolLevels(toolLevels)
        }
    }
}

// MARK: - Presets

extension PermissionConfiguration {

    /// Permissive configuration - allows most operations.
    public static var permissive: PermissionConfiguration {
        PermissionConfiguration(
            defaultMode: .acceptEdits,
            allow: [
                "Read", "Glob", "Grep",
                "Write", "Edit", "MultiEdit",
                "WebFetch", "WebSearch",
                "Git", "Bash"
            ],
            deny: [
                "Bash(rm -rf /)",
                "Bash(sudo:*)"
            ],
            ask: []
        )
    }

    /// Restrictive configuration - requires confirmation for modifications.
    public static var restrictive: PermissionConfiguration {
        PermissionConfiguration(
            defaultMode: .default,
            allow: [
                "Read", "Glob", "Grep",
                "WebFetch(domain:github.com)",
                "WebFetch(domain:developer.apple.com)"
            ],
            deny: [
                "Bash(rm:*)",
                "Bash(sudo:*)",
                "Edit(.env)",
                "Edit(*.pem)",
                "Edit(*.key)",
                "Edit(*secret*)",
                "Edit(*credential*)"
            ],
            ask: [
                "Write", "Edit", "MultiEdit",
                "Bash", "Git"
            ]
        )
    }

    /// Read-only configuration - only allows read operations.
    public static var readOnly: PermissionConfiguration {
        PermissionConfiguration(
            defaultMode: .plan,
            allow: [
                "Read", "Glob", "Grep",
                "WebFetch", "WebSearch"
            ],
            deny: [
                "Write", "Edit", "MultiEdit",
                "Bash", "Git", "ExecuteCommand"
            ],
            ask: []
        )
    }

    /// Development configuration - optimized for development workflows.
    public static var development: PermissionConfiguration {
        PermissionConfiguration(
            defaultMode: .default,
            allow: [
                "Read", "Glob", "Grep",
                "WebFetch(domain:github.com)",
                "WebFetch(domain:stackoverflow.com)",
                "WebFetch(domain:developer.apple.com)",
                "Bash(swift build:*)",
                "Bash(swift test:*)",
                "Bash(swift package:*)",
                "Bash(git status:*)",
                "Bash(git diff:*)",
                "Bash(git log:*)",
                "Bash(npm run:*)",
                "Bash(npm test:*)"
            ],
            deny: [
                "Bash(rm -rf /)",
                "Bash(sudo:*)",
                "Edit(.env)",
                "Edit(*.pem)",
                "Edit(*.key)"
            ],
            ask: [
                "Write", "Edit",
                "Bash(git push:*)",
                "Bash(git commit:*)"
            ]
        )
    }

    /// Bypass configuration - no permission checks.
    ///
    /// - Warning: Only use in trusted, sandboxed environments.
    public static var bypass: PermissionConfiguration {
        PermissionConfiguration(
            defaultMode: .bypassPermissions,
            allow: ["*"],
            deny: [],
            ask: []
        )
    }
}

// MARK: - Codable

extension ToolPermissionLevel: Codable {

    public init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        let value = try container.decode(String.self)

        switch value.lowercased() {
        case "readonly", "read_only", "read-only":
            self = .readOnly
        case "standard":
            self = .standard
        case "elevated":
            self = .elevated
        case "dangerous":
            self = .dangerous
        default:
            throw DecodingError.dataCorruptedError(
                in: container,
                debugDescription: "Unknown permission level: \(value)"
            )
        }
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(self.description.lowercased().replacingOccurrences(of: " ", with: "_"))
    }
}
