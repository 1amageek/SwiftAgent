//
//  ToolMatcher.swift
//  SwiftAgent
//
//  Created by SwiftAgent on 2025/01/23.
//

import Foundation

/// A matcher that determines if a tool invocation matches a pattern.
///
/// `ToolMatcher` supports various pattern syntaxes for matching tool names
/// and their arguments, similar to Claude Code's permission patterns.
///
/// ## Pattern Types
///
/// ### Tool Name Patterns
/// - Exact match: `"Bash"` matches only the Bash tool
/// - Regex: `"Edit|Write"` matches Edit or Write
/// - Wildcard: `"mcp__*"` matches all MCP tools
/// - All tools: `"*"` matches any tool
///
/// ### Argument Patterns
/// - Prefix match: `"npm run:*"` matches commands starting with "npm run"
/// - Glob pattern: `"/src/**/*.swift"` matches paths
/// - Domain: `"domain:github.com"` for WebFetch URLs
/// - Key-value: `"key:value"` for specific argument matching
///
/// ## Usage
///
/// ```swift
/// let matcher = ToolMatcher(pattern: "Bash(npm:*)")
/// let matches = matcher.matches(toolName: "Bash", arguments: "{\"command\": \"npm run test\"}")
/// ```
public struct ToolMatcher: Sendable, Equatable {

    /// The original pattern string.
    public let pattern: String

    /// The tool name pattern.
    public let toolPattern: String

    /// The argument pattern (optional).
    public let argumentPattern: String?

    /// Compiled regex for tool name matching.
    private let toolRegex: NSRegularExpression?

    /// Creates a matcher from a pattern string.
    ///
    /// - Parameter pattern: The pattern (e.g., "Bash(npm:*)").
    public init(pattern: String) {
        self.pattern = pattern

        // Parse pattern
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

        // Compile tool regex
        self.toolRegex = Self.compileToolPattern(toolPattern)
    }

    /// Creates a matcher with explicit components.
    ///
    /// - Parameters:
    ///   - toolPattern: The tool name pattern.
    ///   - argumentPattern: Optional argument pattern.
    public init(toolPattern: String, argumentPattern: String? = nil) {
        self.toolPattern = toolPattern
        self.argumentPattern = argumentPattern

        if let argPattern = argumentPattern {
            self.pattern = "\(toolPattern)(\(argPattern))"
        } else {
            self.pattern = toolPattern
        }

        self.toolRegex = Self.compileToolPattern(toolPattern)
    }

    /// Checks if this matcher matches the given tool invocation.
    ///
    /// - Parameters:
    ///   - toolName: The name of the tool being invoked.
    ///   - arguments: The JSON-encoded arguments (optional).
    /// - Returns: `true` if the invocation matches this pattern.
    public func matches(toolName: String, arguments: String? = nil) -> Bool {
        // Check tool name match
        guard matchesToolName(toolName) else {
            return false
        }

        // If no argument pattern, tool name match is sufficient
        guard let argPattern = argumentPattern else {
            return true
        }

        // Check argument match
        return matchesArguments(argPattern, arguments: arguments ?? "")
    }

    // MARK: - Private Methods

    private func matchesToolName(_ name: String) -> Bool {
        // Wildcard matches everything
        if toolPattern == "*" {
            return true
        }

        // MCP wildcard pattern
        if toolPattern.hasSuffix("*") {
            let prefix = String(toolPattern.dropLast())
            return name.hasPrefix(prefix)
        }

        // Regex match
        if let regex = toolRegex {
            let range = NSRange(name.startIndex..., in: name)
            return regex.firstMatch(in: name, options: [], range: range) != nil
        }

        // Exact match
        return name == toolPattern
    }

    private func matchesArguments(_ pattern: String, arguments: String) -> Bool {
        // Domain pattern for WebFetch
        if pattern.hasPrefix("domain:") {
            let domain = String(pattern.dropFirst(7))
            return matchesDomain(domain, in: arguments)
        }

        // Prefix pattern with wildcard
        if pattern.hasSuffix(":*") {
            let prefix = String(pattern.dropLast(2))
            return matchesPrefix(prefix, in: arguments)
        }

        // Glob pattern for paths
        if pattern.contains("*") || pattern.contains("**") {
            return matchesGlobPattern(pattern, in: arguments)
        }

        // Substring match
        return arguments.contains(pattern)
    }

    private func matchesDomain(_ domain: String, in arguments: String) -> Bool {
        // Check if URL in arguments contains the domain
        // Parse JSON to get URL field
        guard let data = arguments.data(using: .utf8),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return arguments.contains(domain)
        }

        // Check url field
        if let url = json["url"] as? String {
            return url.contains(domain)
        }

        // Check any string value
        for value in json.values {
            if let str = value as? String, str.contains(domain) {
                return true
            }
        }

        return false
    }

    private func matchesPrefix(_ prefix: String, in arguments: String) -> Bool {
        // Parse JSON to check command or other fields
        guard let data = arguments.data(using: .utf8),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return arguments.contains(prefix)
        }

        // Check command field (for Bash)
        if let command = json["command"] as? String {
            return command.hasPrefix(prefix) || command.contains(" \(prefix)")
        }

        // Check executable + args (for ExecuteCommand)
        if let executable = json["executable"] as? String {
            if executable.hasPrefix(prefix) || executable == prefix {
                return true
            }
        }

        // Check argsJson
        if let argsJson = json["argsJson"] as? String,
           argsJson.contains(prefix) {
            return true
        }

        return arguments.contains(prefix)
    }

    private func matchesGlobPattern(_ pattern: String, in arguments: String) -> Bool {
        // Parse JSON to get path fields
        guard let data = arguments.data(using: .utf8),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return matchesGlob(pattern: pattern, path: arguments)
        }

        // Check common path fields
        let pathFields = ["path", "file_path", "filePath", "basePath", "directory"]
        for field in pathFields {
            if let path = json[field] as? String {
                if matchesGlob(pattern: pattern, path: path) {
                    return true
                }
            }
        }

        return false
    }

    private func matchesGlob(pattern: String, path: String) -> Bool {
        // Convert glob pattern to regex
        var regexPattern = pattern
            .replacingOccurrences(of: ".", with: "\\.")
            .replacingOccurrences(of: "**", with: "<<<GLOBSTAR>>>")
            .replacingOccurrences(of: "*", with: "[^/]*")
            .replacingOccurrences(of: "<<<GLOBSTAR>>>", with: ".*")

        regexPattern = "^" + regexPattern + "$"

        guard let regex = try? NSRegularExpression(pattern: regexPattern, options: []) else {
            return false
        }

        let range = NSRange(path.startIndex..., in: path)
        return regex.firstMatch(in: path, options: [], range: range) != nil
    }

    private static func compileToolPattern(_ pattern: String) -> NSRegularExpression? {
        // Skip compilation for simple patterns
        if pattern == "*" || pattern.hasSuffix("*") {
            return nil
        }

        // Check if pattern contains regex metacharacters
        let regexChars = CharacterSet(charactersIn: "|()[]{}^$+?\\")
        guard pattern.unicodeScalars.contains(where: { regexChars.contains($0) }) else {
            return nil
        }

        // Compile as regex
        return try? NSRegularExpression(pattern: "^(\(pattern))$", options: [])
    }

    // MARK: - Equatable

    public static func == (lhs: ToolMatcher, rhs: ToolMatcher) -> Bool {
        lhs.pattern == rhs.pattern
    }
}

// MARK: - Convenience Initializers

extension ToolMatcher {

    /// Creates a matcher for a specific tool.
    public static func tool(_ name: String) -> ToolMatcher {
        ToolMatcher(pattern: name)
    }

    /// Creates a matcher for a tool with an argument pattern.
    public static func tool(_ name: String, arguments: String) -> ToolMatcher {
        ToolMatcher(pattern: "\(name)(\(arguments))")
    }

    /// Creates a matcher for all tools.
    public static var all: ToolMatcher {
        ToolMatcher(pattern: "*")
    }

    /// Creates a matcher for all MCP tools.
    public static var allMCP: ToolMatcher {
        ToolMatcher(pattern: "mcp__*")
    }

    /// Creates a matcher for a specific MCP server.
    public static func mcp(server: String) -> ToolMatcher {
        ToolMatcher(pattern: "mcp__\(server)__*")
    }
}

// MARK: - CustomStringConvertible

extension ToolMatcher: CustomStringConvertible {

    public var description: String {
        pattern
    }
}
