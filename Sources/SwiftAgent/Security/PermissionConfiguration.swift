//
//  PermissionConfiguration.swift
//  SwiftAgent
//
//  Created by SwiftAgent on 2025/01/04.
//

import Foundation

/// Permission decision types.
///
/// Compatible with Claude Code's permission system.
public enum PermissionDecision: String, Sendable, Codable {
    /// Allow the tool execution.
    case allow
    /// Deny the tool execution.
    case deny
    /// Ask the user for permission.
    case ask
}

/// Claude Code-style permission configuration.
///
/// Defines allow and deny rules for tool execution, with support for
/// pattern matching and interactive user confirmation.
///
/// ## Example
///
/// ```swift
/// let config = PermissionConfiguration(
///     allow: [
///         .tool("Read"),
///         .bash("git:*"),
///         .bash("ls:*"),
///     ],
///     deny: [
///         .bash("rm -rf /"),
///         .bash("sudo:*"),
///     ],
///     defaultAction: .ask,
///     handler: CLIPermissionHandler()
/// )
/// ```
///
/// ## Rule Evaluation Order
///
/// 1. Session memory (alwaysAllow / blocked)
/// 2. Allow rules (first match wins)
/// 3. Deny rules (first match wins)
/// 4. Default action
public struct PermissionConfiguration: Sendable {

    /// Allowed patterns (checked first after session memory).
    public var allow: [PermissionRule]

    /// Denied patterns (checked after allow rules).
    public var deny: [PermissionRule]

    /// Default action when no rule matches.
    public var defaultAction: PermissionDecision

    /// Handler for "ask" decisions.
    public var handler: (any PermissionHandler)?

    /// Whether to remember "always allow" and "block" decisions within the session.
    public var enableSessionMemory: Bool

    /// Creates a permission configuration.
    ///
    /// - Parameters:
    ///   - allow: Patterns to allow.
    ///   - deny: Patterns to deny.
    ///   - defaultAction: Action when no rule matches.
    ///   - handler: Handler for interactive confirmation.
    ///   - enableSessionMemory: Whether to remember session decisions.
    public init(
        allow: [PermissionRule] = [],
        deny: [PermissionRule] = [],
        defaultAction: PermissionDecision = .ask,
        handler: (any PermissionHandler)? = nil,
        enableSessionMemory: Bool = true
    ) {
        self.allow = allow
        self.deny = deny
        self.defaultAction = defaultAction
        self.handler = handler
        self.enableSessionMemory = enableSessionMemory
    }
}

// MARK: - Presets

extension PermissionConfiguration {

    /// Standard configuration with sensible defaults.
    ///
    /// - Read-only tools are allowed
    /// - Common safe git/shell commands are allowed
    /// - Dangerous commands are denied
    /// - Everything else prompts the user
    public static var standard: PermissionConfiguration {
        PermissionConfiguration(
            allow: [
                // Read-only tools
                .tool("Read"),
                .tool("Glob"),
                .tool("Grep"),

                // Safe git commands
                .bash("git status"),
                .bash("git log:*"),
                .bash("git diff:*"),
                .bash("git branch:*"),
                .bash("git show:*"),

                // Safe shell commands
                .bash("ls:*"),
                .bash("cat:*"),
                .bash("head:*"),
                .bash("tail:*"),
                .bash("wc:*"),
                .bash("pwd"),
                .bash("whoami"),
                .bash("date"),
                .bash("which:*"),
            ],
            deny: [
                // Dangerous commands (use prefix match to prevent bypass)
                .bash("rm -rf:*"),
                .bash("rm -fr:*"),
                .bash("rm -r -f:*"),
                .bash("rm -f -r:*"),
                .bash("sudo:*"),
                .bash("chmod 777:*"),
                .bash("chmod -R 777:*"),
                .bash("mkfs:*"),
                .bash("dd:*"),
                .bash("> /dev/sd:*"),
                .bash("mv /*:*"),
            ],
            defaultAction: .ask,
            enableSessionMemory: true
        )
    }

    /// Development configuration (permissive).
    ///
    /// - Most tools are allowed
    /// - Only the most dangerous commands are denied
    /// - No user prompts
    public static var development: PermissionConfiguration {
        PermissionConfiguration(
            allow: [
                "*"  // Allow all tools
            ],
            deny: [
                .bash("rm -rf:*"),
                .bash("rm -fr:*"),
                .bash("sudo:*"),
            ],
            defaultAction: .allow,
            enableSessionMemory: false
        )
    }

    /// Restrictive configuration (secure).
    ///
    /// - Only read-only tools are allowed
    /// - Everything else is denied
    public static var restrictive: PermissionConfiguration {
        PermissionConfiguration(
            allow: [
                .tool("Read"),
                .tool("Glob"),
                .tool("Grep"),
            ],
            deny: [],
            defaultAction: .deny,
            enableSessionMemory: false
        )
    }

    /// Read-only configuration.
    ///
    /// - Read tools are allowed
    /// - Write/Execute tools are denied
    public static var readOnly: PermissionConfiguration {
        PermissionConfiguration(
            allow: [
                .tool("Read"),
                .tool("Glob"),
                .tool("Grep"),
            ],
            deny: [
                .tool("Write"),
                .tool("Edit"),
                .tool("MultiEdit"),
                .tool("Bash"),
                .tool("Git"),
            ],
            defaultAction: .deny,
            enableSessionMemory: false
        )
    }
}

// MARK: - Builder Methods

extension PermissionConfiguration {

    /// Returns a copy with a permission handler.
    ///
    /// - Parameter handler: The permission handler.
    /// - Returns: A new configuration with the handler set.
    public func withHandler(_ handler: any PermissionHandler) -> PermissionConfiguration {
        var copy = self
        copy.handler = handler
        return copy
    }

    /// Returns a copy with an additional allow rule.
    ///
    /// - Parameter rule: The rule to add.
    /// - Returns: A new configuration with the rule added.
    public func allowing(_ rule: PermissionRule) -> PermissionConfiguration {
        var copy = self
        copy.allow.append(rule)
        return copy
    }

    /// Returns a copy with an additional deny rule.
    ///
    /// - Parameter rule: The rule to add.
    /// - Returns: A new configuration with the rule added.
    public func denying(_ rule: PermissionRule) -> PermissionConfiguration {
        var copy = self
        copy.deny.append(rule)
        return copy
    }

    /// Returns a copy with session memory enabled/disabled.
    ///
    /// - Parameter enabled: Whether to enable session memory.
    /// - Returns: A new configuration.
    public func withSessionMemory(_ enabled: Bool) -> PermissionConfiguration {
        var copy = self
        copy.enableSessionMemory = enabled
        return copy
    }
}

// MARK: - File Loading & Encoding

/// Internal structure for JSON file format.
///
/// Matches the documented JSON schema:
/// ```json
/// {
///   "version": 1,
///   "permissions": {
///     "allow": ["Read", "Bash(git:*)"],
///     "deny": ["Bash(rm -rf:*)"],
///     "defaultAction": "ask",
///     "enableSessionMemory": true
///   }
/// }
/// ```
private struct PermissionConfigurationFile: Codable {
    var version: Int?
    var permissions: PermissionsData

    struct PermissionsData: Codable {
        var allow: [PermissionRule]
        var deny: [PermissionRule]
        var defaultAction: PermissionDecision?
        var enableSessionMemory: Bool?
    }
}

extension PermissionConfiguration {

    /// Current schema version.
    public static let schemaVersion = 1

    // MARK: - Loading

    /// Loads a permission configuration from a URL.
    ///
    /// - Parameter url: The URL to load from.
    /// - Returns: The loaded configuration.
    /// - Throws: File reading or JSON decoding errors.
    ///
    /// ## Example
    ///
    /// ```swift
    /// let config = try PermissionConfiguration.load(from: configURL)
    /// ```
    public static func load(from url: URL) throws -> PermissionConfiguration {
        let data = try Data(contentsOf: url)
        return try load(from: data)
    }

    /// Loads a permission configuration from JSON data.
    ///
    /// - Parameter data: The JSON data to parse.
    /// - Returns: The loaded configuration.
    /// - Throws: JSON decoding errors.
    ///
    /// ## Example
    ///
    /// ```swift
    /// let jsonData = """
    /// {
    ///   "permissions": {
    ///     "allow": ["Read"],
    ///     "deny": []
    ///   }
    /// }
    /// """.data(using: .utf8)!
    ///
    /// let config = try PermissionConfiguration.load(from: jsonData)
    /// ```
    public static func load(from data: Data) throws -> PermissionConfiguration {
        let decoder = JSONDecoder()
        let file = try decoder.decode(PermissionConfigurationFile.self, from: data)

        return PermissionConfiguration(
            allow: file.permissions.allow,
            deny: file.permissions.deny,
            defaultAction: file.permissions.defaultAction ?? .ask,
            handler: nil,  // handler cannot be loaded from file
            enableSessionMemory: file.permissions.enableSessionMemory ?? true
        )
    }

    // MARK: - Encoding

    /// Encodes this configuration to JSON data.
    ///
    /// - Returns: The JSON-encoded data.
    /// - Throws: JSON encoding errors.
    ///
    /// ## Example
    ///
    /// ```swift
    /// let data = try config.encode()
    /// try data.write(to: saveURL)
    /// ```
    ///
    /// - Note: The `handler` property is not included in the output
    ///   as it cannot be serialized.
    public func encode() throws -> Data {
        let file = PermissionConfigurationFile(
            version: Self.schemaVersion,
            permissions: .init(
                allow: allow,
                deny: deny,
                defaultAction: defaultAction,
                enableSessionMemory: enableSessionMemory
            )
        )

        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        return try encoder.encode(file)
    }

    // MARK: - Merging

    /// Merges this configuration with another.
    ///
    /// The `other` configuration takes precedence for scalar values
    /// (`defaultAction`, `enableSessionMemory`). Rules are concatenated
    /// with duplicates removed (preserving order, keeping first occurrence).
    ///
    /// - Parameter other: The configuration to merge with.
    /// - Returns: A merged configuration.
    ///
    /// ## Example
    ///
    /// ```swift
    /// let base = PermissionConfiguration.standard
    /// let override = try PermissionConfiguration.load(from: userConfigURL)
    /// let merged = base.merged(with: override)
    /// ```
    public func merged(with other: PermissionConfiguration) -> PermissionConfiguration {
        PermissionConfiguration(
            allow: Self.deduplicateRules(allow + other.allow),
            deny: Self.deduplicateRules(deny + other.deny),
            defaultAction: other.defaultAction,
            handler: other.handler ?? handler,
            enableSessionMemory: other.enableSessionMemory
        )
    }

    /// Removes duplicate rules while preserving order (keeps first occurrence).
    private static func deduplicateRules(_ rules: [PermissionRule]) -> [PermissionRule] {
        var seen = Set<PermissionRule>()
        return rules.filter { seen.insert($0).inserted }
    }

    /// Merges multiple configurations in order.
    ///
    /// Later configurations take precedence over earlier ones.
    ///
    /// - Parameter configurations: The configurations to merge.
    /// - Returns: A merged configuration.
    ///
    /// ## Example
    ///
    /// ```swift
    /// let merged = PermissionConfiguration.merge([
    ///     .standard,           // base
    ///     userConfig,          // user overrides
    ///     projectConfig        // project overrides (highest priority)
    /// ])
    /// ```
    public static func merge(_ configurations: [PermissionConfiguration]) -> PermissionConfiguration {
        guard let first = configurations.first else {
            return PermissionConfiguration()
        }
        return configurations.dropFirst().reduce(first) { $0.merged(with: $1) }
    }
}
