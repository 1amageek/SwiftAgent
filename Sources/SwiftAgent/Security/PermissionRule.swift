//
//  PermissionRule.swift
//  SwiftAgent
//
//  Created by SwiftAgent on 2025/01/04.
//

import Foundation

/// Permission rule with Claude Code-style pattern syntax.
///
/// Supports patterns like:
/// - `"Read"` - matches tool name exactly
/// - `"Bash(git:*)"` - matches Bash tool with git commands
/// - `"Bash(git status)"` - matches exact command
/// - `"Write(/tmp/*)"` - matches Write to /tmp paths
/// - `"mcp__server__*"` - wildcard for MCP tools
///
/// ## Pattern Syntax
///
/// ```
/// ToolName                    - Exact tool name match
/// ToolName(argument_pattern)  - Tool name + argument pattern
/// Tool*                       - Wildcard in tool name
/// ToolName(prefix:*)          - Argument is prefix or starts with prefix + separator
/// ```
///
/// ## Separator Characters for `prefix:*` Patterns
///
/// The `prefix:*` pattern matches if:
/// - The value equals the prefix exactly, OR
/// - The value starts with prefix followed by a separator character
///
/// Recognized separators: space ` `, dash `-`, tab `\t`, semicolon `;`,
/// pipe `|`, ampersand `&`, newline `\n`
///
/// Example: `git:*` matches `git`, `git status`, `git-flow` but NOT `gitsomething`
public struct PermissionRule: Sendable, Equatable, Hashable {

    /// The raw pattern string.
    public let pattern: String

    /// Creates a permission rule from a pattern string.
    ///
    /// - Parameter pattern: The pattern string (e.g., "Bash(git:*)")
    public init(_ pattern: String) {
        self.pattern = pattern
    }

    // MARK: - Parsed Components

    /// The tool name part of the pattern.
    ///
    /// Examples:
    /// - `"Read"` → `"Read"`
    /// - `"Bash(git:*)"` → `"Bash"`
    /// - `"mcp__server__*"` → `"mcp__server__*"`
    public var toolName: String {
        if let parenIndex = pattern.firstIndex(of: "(") {
            return String(pattern[..<parenIndex])
        }
        return pattern
    }

    /// The argument pattern part (if any).
    ///
    /// Examples:
    /// - `"Read"` → `nil`
    /// - `"Bash(git:*)"` → `"git:*"`
    /// - `"Write(/tmp/*)"` → `"/tmp/*"`
    public var argumentPattern: String? {
        guard let startIndex = pattern.firstIndex(of: "("),
              let endIndex = pattern.lastIndex(of: ")") else {
            return nil
        }
        let start = pattern.index(after: startIndex)
        guard start < endIndex else { return nil }
        return String(pattern[start..<endIndex])
    }

    // MARK: - Matching

    /// Matches this rule against a tool context.
    ///
    /// - Parameter context: The tool context to match against.
    /// - Returns: `true` if the rule matches the context.
    public func matches(_ context: ToolContext) -> Bool {
        // First, match the tool name
        guard matchesToolName(context.toolName) else {
            return false
        }

        // If no argument pattern, tool name match is sufficient
        guard let argPattern = argumentPattern else {
            return true
        }

        // Match argument pattern against the appropriate field
        return matchesArgument(argPattern, context: context)
    }

    private func matchesToolName(_ name: String) -> Bool {
        let toolPattern = self.toolName

        // Exact match
        if toolPattern == name {
            return true
        }

        // Wildcard match
        if toolPattern.contains("*") {
            return matchWildcard(toolPattern, against: name)
        }

        return false
    }

    private func matchesArgument(_ argPattern: String, context: ToolContext) -> Bool {
        // Parse the argument JSON
        guard let data = context.arguments.data(using: .utf8),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return false
        }

        // For Bash tool, match against "command" field
        if context.toolName == "Bash" || context.toolName == "ExecuteCommand" {
            if let command = json["command"] as? String {
                return matchArgumentPattern(argPattern, against: command)
            }
        }

        // For Write/Edit tools, match against "file_path" field (with path normalization)
        if context.toolName == "Write" || context.toolName == "Edit" || context.toolName == "MultiEdit" {
            if let filePath = json["file_path"] as? String {
                let normalizedPath = normalizePath(filePath)
                return matchArgumentPattern(argPattern, against: normalizedPath)
            }
        }

        // For Read tool, match against "file_path" field (with path normalization)
        if context.toolName == "Read" {
            if let filePath = json["file_path"] as? String {
                let normalizedPath = normalizePath(filePath)
                return matchArgumentPattern(argPattern, against: normalizedPath)
            }
        }

        // For Glob/Grep tools, match against "path" field (with path normalization)
        if context.toolName == "Glob" || context.toolName == "Grep" {
            if let path = json["path"] as? String {
                let normalizedPath = normalizePath(path)
                return matchArgumentPattern(argPattern, against: normalizedPath)
            }
        }

        // Generic: try to match against any string value
        for (_, value) in json {
            if let stringValue = value as? String {
                if matchArgumentPattern(argPattern, against: stringValue) {
                    return true
                }
            }
        }

        return false
    }

    /// Normalizes a file path by resolving `.` and `..` components.
    ///
    /// This provides defense-in-depth against path traversal attempts
    /// in permission rules, complementing the tool-level path validation.
    ///
    /// - Parameter path: The path to normalize.
    /// - Returns: The normalized path with `.` and `..` resolved.
    private func normalizePath(_ path: String) -> String {
        // Use URL.standardized to resolve . and .. components
        URL(fileURLWithPath: path).standardized.path
    }

    /// Separator characters recognized for `prefix:*` patterns.
    ///
    /// These are command/path separators that indicate the prefix
    /// is a distinct token rather than part of a longer word.
    private static let prefixSeparators: [Character] = [
        " ",   // space (most common)
        "-",   // dash (e.g., git-flow)
        "\t",  // tab
        ";",   // semicolon (command separator)
        "|",   // pipe
        "&",   // ampersand (background/and)
        "\n",  // newline
        "/",   // path separator
    ]

    private func matchArgumentPattern(_ pattern: String, against value: String) -> Bool {
        // Handle "prefix:*" pattern (Claude Code style)
        if pattern.hasSuffix(":*") {
            let prefix = String(pattern.dropLast(2))

            // Exact match (prefix with nothing after)
            if value == prefix {
                return true
            }

            // Match if value starts with prefix followed by a separator
            for separator in Self.prefixSeparators {
                if value.hasPrefix(prefix + String(separator)) {
                    return true
                }
            }

            return false
        }

        // Handle general wildcard pattern
        if pattern.contains("*") {
            return matchWildcard(pattern, against: value)
        }

        // Exact match
        return pattern == value
    }

    /// Matches a wildcard pattern against a string.
    ///
    /// - Parameters:
    ///   - pattern: Pattern with `*` wildcards.
    ///   - string: String to match against.
    /// - Returns: `true` if the pattern matches.
    ///
    /// - Note: Matching is case-sensitive to match exact match behavior.
    private func matchWildcard(_ pattern: String, against string: String) -> Bool {
        // Convert wildcard pattern to regex
        let escaped = NSRegularExpression.escapedPattern(for: pattern)
        let regexPattern = "^" + escaped.replacingOccurrences(of: "\\*", with: ".*") + "$"

        guard let regex = try? NSRegularExpression(pattern: regexPattern, options: []) else {
            return false
        }

        let range = NSRange(string.startIndex..., in: string)
        return regex.firstMatch(in: string, options: [], range: range) != nil
    }
}

// MARK: - Factory Methods

extension PermissionRule {

    /// Creates a rule that matches a tool name exactly.
    ///
    /// - Parameter name: The tool name.
    /// - Returns: A permission rule.
    public static func tool(_ name: String) -> PermissionRule {
        PermissionRule(name)
    }

    /// Creates a rule that matches Bash commands.
    ///
    /// - Parameter commandPattern: The command pattern (e.g., "git:*", "ls -la").
    /// - Returns: A permission rule.
    public static func bash(_ commandPattern: String) -> PermissionRule {
        PermissionRule("Bash(\(commandPattern))")
    }

    /// Creates a rule that matches Write operations to specific paths.
    ///
    /// - Parameter pathPattern: The path pattern (e.g., "/tmp/*").
    /// - Returns: A permission rule.
    public static func write(_ pathPattern: String) -> PermissionRule {
        PermissionRule("Write(\(pathPattern))")
    }

    /// Creates a rule that matches Edit operations to specific paths.
    ///
    /// - Parameter pathPattern: The path pattern.
    /// - Returns: A permission rule.
    public static func edit(_ pathPattern: String) -> PermissionRule {
        PermissionRule("Edit(\(pathPattern))")
    }

    /// Creates a rule that matches Read operations to specific paths.
    ///
    /// - Parameter pathPattern: The path pattern.
    /// - Returns: A permission rule.
    public static func read(_ pathPattern: String) -> PermissionRule {
        PermissionRule("Read(\(pathPattern))")
    }

    /// Creates a rule that matches all MCP tools from a server.
    ///
    /// - Parameter serverName: The MCP server name.
    /// - Returns: A permission rule.
    public static func mcp(_ serverName: String) -> PermissionRule {
        PermissionRule("mcp__\(serverName)__*")
    }
}

// MARK: - ExpressibleByStringLiteral

extension PermissionRule: ExpressibleByStringLiteral {
    public init(stringLiteral value: String) {
        self.init(value)
    }
}

// MARK: - CustomStringConvertible

extension PermissionRule: CustomStringConvertible {
    public var description: String {
        pattern
    }
}

// MARK: - Codable

extension PermissionRule: Codable {
    public init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        self.pattern = try container.decode(String.self)
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(pattern)
    }
}

// MARK: - Parsing

extension PermissionRule {

    /// Parses a space-delimited string of permission patterns.
    ///
    /// This is used to parse the `allowed-tools` field from SKILL.md frontmatter.
    /// Patterns can include parentheses for argument patterns, and spaces inside
    /// parentheses are preserved.
    ///
    /// ## Example
    ///
    /// ```swift
    /// let rules = PermissionRule.parse("Bash(git:*) Read Write")
    /// // Returns: [PermissionRule("Bash(git:*)"), PermissionRule("Read"), PermissionRule("Write")]
    /// ```
    ///
    /// - Parameter string: Space-delimited patterns (e.g., "Bash(git:*) Read Write").
    /// - Returns: Array of parsed PermissionRule objects.
    public static func parse(_ string: String) -> [PermissionRule] {
        var rules: [PermissionRule] = []
        var current = ""
        var parenDepth = 0

        for char in string {
            if char == "(" {
                parenDepth += 1
                current.append(char)
            } else if char == ")" {
                parenDepth -= 1
                current.append(char)
            } else if char.isWhitespace && parenDepth == 0 {
                if !current.isEmpty {
                    rules.append(PermissionRule(current))
                    current = ""
                }
            } else {
                current.append(char)
            }
        }

        if !current.isEmpty {
            rules.append(PermissionRule(current))
        }

        return rules
    }
}
