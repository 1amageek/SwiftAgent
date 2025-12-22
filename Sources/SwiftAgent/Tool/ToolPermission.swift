//
//  ToolPermission.swift
//  SwiftAgent
//
//  Created by SwiftAgent on 2025/01/15.
//

import Foundation

/// A delegate that controls whether tools can be used.
///
/// Implement this protocol to add custom permission logic for tool execution.
/// This allows you to restrict certain tools based on context, user permissions,
/// or other criteria.
///
/// ## Usage
///
/// ```swift
/// struct MyPermissionDelegate: ToolPermissionDelegate {
///     func canUseTool(
///         named toolName: String,
///         arguments: String,
///         context: ToolPermissionContext
///     ) async throws -> ToolPermissionResult {
///         // Block dangerous tools
///         if toolName == "ExecuteCommandTool" {
///             return .deny(reason: "Command execution is not allowed")
///         }
///         return .allow
///     }
/// }
/// ```
public protocol ToolPermissionDelegate: Sendable {

    /// Determines whether a tool can be used.
    ///
    /// - Parameters:
    ///   - toolName: The name of the tool being checked.
    ///   - arguments: The JSON-encoded arguments for the tool.
    ///   - context: Context information about the current session and turn.
    /// - Returns: A result indicating whether the tool can be used.
    func canUseTool(
        named toolName: String,
        arguments: String,
        context: ToolPermissionContext
    ) async throws -> ToolPermissionResult
}

// MARK: - ToolPermissionContext

/// Context information for permission checks.
public struct ToolPermissionContext: Sendable {
    /// The session ID, if available.
    public let sessionID: String?

    /// The current turn number in the conversation.
    public let turnNumber: Int

    /// Names of tools that have already been called in this turn.
    public let previousToolCalls: [String]

    /// Creates a permission context.
    public init(
        sessionID: String? = nil,
        turnNumber: Int = 0,
        previousToolCalls: [String] = []
    ) {
        self.sessionID = sessionID
        self.turnNumber = turnNumber
        self.previousToolCalls = previousToolCalls
    }
}

// MARK: - ToolPermissionResult

/// The result of a permission check.
public enum ToolPermissionResult: Sendable {
    /// Allow the tool to be used.
    case allow

    /// Allow the tool with modified input.
    ///
    /// The pipeline will deserialize the modified JSON back into the tool's
    /// `Arguments` type using `GeneratedContent(json:)` and `T.Arguments(content)`.
    ///
    /// - Parameter modifiedInput: The modified JSON-encoded arguments.
    ///
    /// ## Example
    ///
    /// ```swift
    /// func canUseTool(
    ///     named toolName: String,
    ///     arguments: String,
    ///     context: ToolPermissionContext
    /// ) async throws -> ToolPermissionResult {
    ///     // Mask sensitive data like API keys
    ///     if arguments.contains(apiKey) {
    ///         let masked = arguments.replacingOccurrences(of: apiKey, with: "***REDACTED***")
    ///         return .allowWithModifiedInput(masked)
    ///     }
    ///     return .allow
    /// }
    /// ```
    case allowWithModifiedInput(String)

    /// Deny the tool usage.
    ///
    /// The reason will be returned to the LLM as an error message.
    ///
    /// - Parameter reason: Optional explanation for the denial.
    case deny(reason: String?)

    /// Deny the tool usage and interrupt processing.
    ///
    /// This throws an exception and stops the current agent turn.
    ///
    /// - Parameter reason: Optional explanation for the interruption.
    case denyAndInterrupt(reason: String?)
}

// MARK: - ToolPermissionLevel

/// Represents the danger level of a tool.
///
/// Higher levels indicate more potentially dangerous operations.
public enum ToolPermissionLevel: Int, Sendable, Comparable, CaseIterable {
    /// Read-only operations that don't modify anything.
    ///
    /// Examples: file reading, searching, listing
    case readOnly = 0

    /// Standard operations with limited impact.
    ///
    /// Examples: basic API calls, data processing
    case standard = 1

    /// Elevated operations that modify state.
    ///
    /// Examples: file writing, database modifications
    case elevated = 2

    /// Dangerous operations that could have significant impact.
    ///
    /// Examples: command execution, system modifications
    case dangerous = 3

    public static func < (lhs: ToolPermissionLevel, rhs: ToolPermissionLevel) -> Bool {
        lhs.rawValue < rhs.rawValue
    }

    /// A description of this permission level.
    public var description: String {
        switch self {
        case .readOnly:
            return "Read Only"
        case .standard:
            return "Standard"
        case .elevated:
            return "Elevated"
        case .dangerous:
            return "Dangerous"
        }
    }
}

// MARK: - Convenience Permission Delegates

/// A permission delegate that allows all tools.
public struct AllowAllPermissionDelegate: ToolPermissionDelegate {

    public init() {}

    public func canUseTool(
        named toolName: String,
        arguments: String,
        context: ToolPermissionContext
    ) async throws -> ToolPermissionResult {
        .allow
    }
}

/// A permission delegate that blocks tools above a certain permission level.
public struct PermissionLevelDelegate: ToolPermissionDelegate {

    private let maxLevel: ToolPermissionLevel
    private let toolLevels: [String: ToolPermissionLevel]

    /// Creates a permission level delegate.
    ///
    /// - Parameters:
    ///   - maxLevel: The maximum permission level to allow.
    ///   - toolLevels: A mapping of tool names to their permission levels.
    public init(
        maxLevel: ToolPermissionLevel,
        toolLevels: [String: ToolPermissionLevel] = [:]
    ) {
        self.maxLevel = maxLevel
        self.toolLevels = toolLevels
    }

    public func canUseTool(
        named toolName: String,
        arguments: String,
        context: ToolPermissionContext
    ) async throws -> ToolPermissionResult {
        let level = toolLevels[toolName] ?? .standard

        if level > maxLevel {
            return .deny(reason: "Tool '\(toolName)' requires \(level.description) permission, but only \(maxLevel.description) is allowed")
        }

        return .allow
    }
}

/// A permission delegate that blocks specific tools.
public struct BlockListPermissionDelegate: ToolPermissionDelegate {

    private let blockedTools: Set<String>

    /// Creates a block list permission delegate.
    ///
    /// - Parameter blockedTools: Names of tools to block.
    public init(blockedTools: Set<String>) {
        self.blockedTools = blockedTools
    }

    public func canUseTool(
        named toolName: String,
        arguments: String,
        context: ToolPermissionContext
    ) async throws -> ToolPermissionResult {
        if blockedTools.contains(toolName) {
            return .deny(reason: "Tool '\(toolName)' is not allowed")
        }
        return .allow
    }
}

/// A permission delegate that only allows specific tools.
public struct AllowListPermissionDelegate: ToolPermissionDelegate {

    private let allowedTools: Set<String>

    /// Creates an allow list permission delegate.
    ///
    /// - Parameter allowedTools: Names of tools to allow.
    public init(allowedTools: Set<String>) {
        self.allowedTools = allowedTools
    }

    public func canUseTool(
        named toolName: String,
        arguments: String,
        context: ToolPermissionContext
    ) async throws -> ToolPermissionResult {
        if allowedTools.contains(toolName) {
            return .allow
        }
        return .deny(reason: "Tool '\(toolName)' is not in the allowed list")
    }
}
