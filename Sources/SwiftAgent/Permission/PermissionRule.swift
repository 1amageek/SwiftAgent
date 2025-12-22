//
//  PermissionRule.swift
//  SwiftAgent
//
//  Created by SwiftAgent on 2025/01/23.
//

import Foundation

/// The type of a permission rule.
///
/// Rules are evaluated in order of precedence: deny > ask > allow.
public enum PermissionRuleType: String, Codable, Sendable {
    /// Allow the tool usage without prompting.
    case allow

    /// Deny the tool usage entirely.
    case deny

    /// Ask for confirmation before allowing.
    case ask
}

/// A permission rule that controls tool access.
///
/// Permission rules use pattern matching to determine whether a tool
/// can be used. Rules can match on tool name and optionally on arguments.
///
/// ## Pattern Syntax
///
/// ### Tool Name Patterns
/// - Simple match: `"Bash"` matches the Bash tool
/// - Regex: `"Edit|Write"` matches Edit or Write tools
/// - MCP wildcard: `"mcp__*"` matches all MCP tools
/// - MCP specific: `"mcp__filesystem__*"` matches all filesystem MCP tools
///
/// ### Argument Patterns
/// - Prefix match: `"npm run:*"` matches npm run commands
/// - Glob pattern: `"/src/**/*.swift"` matches Swift files in src
/// - Domain match: `"domain:github.com"` for WebFetch
///
/// ## Examples
///
/// ```swift
/// // Allow all read operations
/// PermissionRule(type: .allow, pattern: "Read")
///
/// // Deny dangerous commands
/// PermissionRule(type: .deny, pattern: "Bash(rm -rf:*)")
///
/// // Ask before editing source files
/// PermissionRule(type: .ask, pattern: "Edit(/src/**)")
///
/// // Allow fetching from specific domains
/// PermissionRule(type: .allow, pattern: "WebFetch(domain:github.com)")
/// ```
public struct PermissionRule: Codable, Sendable, Equatable {

    /// The type of this rule (allow, deny, or ask).
    public let type: PermissionRuleType

    /// The pattern string that this rule matches.
    ///
    /// Format: `"ToolName"` or `"ToolName(argumentPattern)"`
    public let pattern: String

    /// The tool name pattern extracted from the pattern string.
    public let toolPattern: String

    /// The argument pattern extracted from the pattern string (if any).
    public let argumentPattern: String?

    /// Creates a permission rule from a pattern string.
    ///
    /// - Parameters:
    ///   - type: The type of rule (allow, deny, or ask).
    ///   - pattern: The pattern string (e.g., "Bash(npm:*)").
    public init(type: PermissionRuleType, pattern: String) {
        self.type = type
        self.pattern = pattern

        // Parse pattern into tool and argument parts
        if let parenStart = pattern.firstIndex(of: "("),
           let parenEnd = pattern.lastIndex(of: ")"),
           parenStart < parenEnd {
            self.toolPattern = String(pattern[..<parenStart])
            let argStart = pattern.index(after: parenStart)
            self.argumentPattern = String(pattern[argStart..<parenEnd])
        } else {
            self.toolPattern = pattern
            self.argumentPattern = nil
        }
    }

    /// Creates a permission rule with explicit components.
    ///
    /// - Parameters:
    ///   - type: The type of rule.
    ///   - toolPattern: The tool name pattern.
    ///   - argumentPattern: Optional argument pattern.
    public init(type: PermissionRuleType, toolPattern: String, argumentPattern: String? = nil) {
        self.type = type
        self.toolPattern = toolPattern
        self.argumentPattern = argumentPattern

        if let argPattern = argumentPattern {
            self.pattern = "\(toolPattern)(\(argPattern))"
        } else {
            self.pattern = toolPattern
        }
    }
}

// MARK: - Convenience Initializers

extension PermissionRule {

    /// Creates an allow rule.
    public static func allow(_ pattern: String) -> PermissionRule {
        PermissionRule(type: .allow, pattern: pattern)
    }

    /// Creates a deny rule.
    public static func deny(_ pattern: String) -> PermissionRule {
        PermissionRule(type: .deny, pattern: pattern)
    }

    /// Creates an ask rule.
    public static func ask(_ pattern: String) -> PermissionRule {
        PermissionRule(type: .ask, pattern: pattern)
    }
}

// MARK: - Common Rules

extension PermissionRule {

    /// Rules for read-only tools.
    public static let readOnlyTools: [PermissionRule] = [
        .allow("Read"),
        .allow("Glob"),
        .allow("Grep")
    ]

    /// Rules for file modification tools.
    public static let fileModificationTools: [PermissionRule] = [
        .ask("Write"),
        .ask("Edit"),
        .ask("MultiEdit")
    ]

    /// Rules for command execution.
    public static let commandExecutionTools: [PermissionRule] = [
        .ask("Bash"),
        .ask("ExecuteCommand")
    ]

    /// Rules to deny dangerous operations.
    public static let denyDangerousOperations: [PermissionRule] = [
        .deny("Bash(rm -rf:*)"),
        .deny("Bash(sudo:*)"),
        .deny("Edit(.env)"),
        .deny("Edit(*.pem)"),
        .deny("Edit(*.key)"),
        .deny("Edit(*credentials*)"),
        .deny("Edit(*secret*)")
    ]

    /// Rules to allow Swift development commands.
    public static let swiftDevelopment: [PermissionRule] = [
        .allow("Bash(swift build:*)"),
        .allow("Bash(swift test:*)"),
        .allow("Bash(swift package:*)"),
        .allow("Bash(swift run:*)")
    ]

    /// Rules to allow npm/node development commands.
    public static let nodeDevelopment: [PermissionRule] = [
        .allow("Bash(npm run:*)"),
        .allow("Bash(npm test:*)"),
        .allow("Bash(npm install:*)"),
        .allow("Bash(yarn:*)"),
        .allow("Bash(npx:*)")
    ]

    /// Rules to allow Git read operations.
    public static let gitReadOperations: [PermissionRule] = [
        .allow("Bash(git status:*)"),
        .allow("Bash(git diff:*)"),
        .allow("Bash(git log:*)"),
        .allow("Bash(git show:*)"),
        .allow("Bash(git branch:*)")
    ]

    /// Rules to require confirmation for Git write operations.
    public static let gitWriteOperations: [PermissionRule] = [
        .ask("Bash(git push:*)"),
        .ask("Bash(git commit:*)"),
        .ask("Bash(git merge:*)"),
        .ask("Bash(git rebase:*)")
    ]

    /// Rules to deny Git destructive operations.
    public static let gitDestructiveOperations: [PermissionRule] = [
        .deny("Bash(git push --force:*)"),
        .deny("Bash(git reset --hard:*)"),
        .deny("Bash(git clean -fd:*)")
    ]

    /// Creates rules to allow web fetching from specific domains.
    public static func allowWebFetch(domains: [String]) -> [PermissionRule] {
        domains.map { .allow("WebFetch(domain:\($0))") }
    }

    /// Creates rules to allow web fetching from common developer domains.
    public static let developerDomains: [PermissionRule] = [
        .allow("WebFetch(domain:github.com)"),
        .allow("WebFetch(domain:developer.apple.com)"),
        .allow("WebFetch(domain:stackoverflow.com)"),
        .allow("WebFetch(domain:docs.swift.org)")
    ]
}

// MARK: - Rule Sets

extension PermissionRule {

    /// A complete rule set for safe development.
    public static var safeDevelopmentRules: [PermissionRule] {
        var rules: [PermissionRule] = []
        rules.append(contentsOf: readOnlyTools)
        rules.append(contentsOf: denyDangerousOperations)
        rules.append(contentsOf: swiftDevelopment)
        rules.append(contentsOf: gitReadOperations)
        rules.append(contentsOf: gitDestructiveOperations)
        rules.append(contentsOf: developerDomains)
        rules.append(contentsOf: fileModificationTools)
        rules.append(contentsOf: gitWriteOperations)
        return rules
    }

    /// A complete rule set for read-only operations.
    public static var readOnlyRules: [PermissionRule] {
        var rules: [PermissionRule] = []
        rules.append(contentsOf: readOnlyTools)
        rules.append(contentsOf: gitReadOperations)
        rules.append(.deny("Write"))
        rules.append(.deny("Edit"))
        rules.append(.deny("MultiEdit"))
        rules.append(.deny("Bash"))
        rules.append(.deny("ExecuteCommand"))
        return rules
    }
}

// MARK: - CustomStringConvertible

extension PermissionRule: CustomStringConvertible {

    public var description: String {
        "\(type.rawValue.capitalized): \(pattern)"
    }
}
