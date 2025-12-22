//
//  ToolExecutionContext.swift
//  SwiftAgent
//
//  Created by SwiftAgent on 2025/01/15.
//

import Foundation

/// Context information for tool execution.
///
/// This struct contains information about the current execution environment,
/// useful for logging, tracing, and permission decisions.
public struct ToolExecutionContext: Sendable {

    /// The session ID, if available.
    public let sessionID: String?

    /// Unique identifier for this tool call.
    public let toolCallID: String

    /// The parent tool call ID if this is a nested call.
    public let parentToolCallID: String?

    /// The current turn number in the conversation.
    public let turnNumber: Int

    /// A trace ID for correlating logs and metrics.
    public let traceID: String?

    /// Custom tags for categorization and filtering.
    public let tags: [String: String]

    /// The permission level of this tool.
    public let permissionLevel: ToolPermissionLevel

    /// When this context was created.
    public let timestamp: Date

    /// Tool calls made earlier in this turn.
    public let previousToolCalls: [String]

    /// Creates a new execution context.
    ///
    /// - Parameters:
    ///   - sessionID: The session ID.
    ///   - toolCallID: The tool call ID. Defaults to a new UUID.
    ///   - parentToolCallID: The parent tool call ID for nested calls.
    ///   - turnNumber: The current turn number.
    ///   - traceID: A trace ID for logging.
    ///   - tags: Custom tags.
    ///   - permissionLevel: The permission level.
    ///   - timestamp: When this context was created. Defaults to now.
    ///   - previousToolCalls: Tool calls made earlier in this turn.
    public init(
        sessionID: String? = nil,
        toolCallID: String = UUID().uuidString,
        parentToolCallID: String? = nil,
        turnNumber: Int = 0,
        traceID: String? = nil,
        tags: [String: String] = [:],
        permissionLevel: ToolPermissionLevel = .standard,
        timestamp: Date = Date(),
        previousToolCalls: [String] = []
    ) {
        self.sessionID = sessionID
        self.toolCallID = toolCallID
        self.parentToolCallID = parentToolCallID
        self.turnNumber = turnNumber
        self.traceID = traceID
        self.tags = tags
        self.permissionLevel = permissionLevel
        self.timestamp = timestamp
        self.previousToolCalls = previousToolCalls
    }

    /// Creates a child context for nested tool calls.
    ///
    /// - Parameter newToolCallID: The ID for the child tool call.
    /// - Returns: A new context with this context as the parent.
    public func child(toolCallID newToolCallID: String = UUID().uuidString) -> ToolExecutionContext {
        ToolExecutionContext(
            sessionID: sessionID,
            toolCallID: newToolCallID,
            parentToolCallID: toolCallID,
            turnNumber: turnNumber,
            traceID: traceID,
            tags: tags,
            permissionLevel: permissionLevel,
            timestamp: Date(),
            previousToolCalls: previousToolCalls
        )
    }

    /// Creates a copy with additional tags.
    ///
    /// - Parameter additionalTags: Tags to add to the context.
    /// - Returns: A new context with the additional tags.
    public func withTags(_ additionalTags: [String: String]) -> ToolExecutionContext {
        var mergedTags = tags
        for (key, value) in additionalTags {
            mergedTags[key] = value
        }

        return ToolExecutionContext(
            sessionID: sessionID,
            toolCallID: toolCallID,
            parentToolCallID: parentToolCallID,
            turnNumber: turnNumber,
            traceID: traceID,
            tags: mergedTags,
            permissionLevel: permissionLevel,
            timestamp: timestamp,
            previousToolCalls: previousToolCalls
        )
    }

    /// Creates a copy with a different permission level.
    ///
    /// - Parameter level: The new permission level.
    /// - Returns: A new context with the updated permission level.
    public func withPermissionLevel(_ level: ToolPermissionLevel) -> ToolExecutionContext {
        ToolExecutionContext(
            sessionID: sessionID,
            toolCallID: toolCallID,
            parentToolCallID: parentToolCallID,
            turnNumber: turnNumber,
            traceID: traceID,
            tags: tags,
            permissionLevel: level,
            timestamp: timestamp,
            previousToolCalls: previousToolCalls
        )
    }

    /// Whether this is a nested tool call.
    public var isNestedCall: Bool {
        parentToolCallID != nil
    }

    /// The nesting depth, starting at 0 for top-level calls.
    public var depth: Int {
        parentToolCallID == nil ? 0 : 1
        // Note: Actual depth tracking would require passing depth through the chain
    }
}

// MARK: - CustomStringConvertible

extension ToolExecutionContext: CustomStringConvertible {
    public var description: String {
        var parts: [String] = []

        if let sessionID = sessionID {
            parts.append("session=\(sessionID)")
        }

        parts.append("toolCallID=\(toolCallID)")

        if let parentID = parentToolCallID {
            parts.append("parentID=\(parentID)")
        }

        parts.append("turn=\(turnNumber)")

        if let traceID = traceID {
            parts.append("trace=\(traceID)")
        }

        parts.append("level=\(permissionLevel.description)")

        return "ToolExecutionContext(\(parts.joined(separator: ", ")))"
    }
}

// MARK: - Factory Methods

extension ToolExecutionContext {

    /// Creates a minimal context for testing.
    public static func forTesting(
        toolCallID: String = "test-call",
        turnNumber: Int = 1
    ) -> ToolExecutionContext {
        ToolExecutionContext(
            sessionID: "test-session",
            toolCallID: toolCallID,
            parentToolCallID: nil,
            turnNumber: turnNumber,
            traceID: "test-trace",
            tags: [:],
            permissionLevel: .standard
        )
    }

    /// Creates a context from an agent session.
    ///
    /// - Parameters:
    ///   - sessionID: The agent session ID.
    ///   - turnNumber: The current turn number.
    ///   - traceID: Optional trace ID.
    /// - Returns: A new execution context.
    public static func fromSession(
        sessionID: String,
        turnNumber: Int,
        traceID: String? = nil
    ) -> ToolExecutionContext {
        ToolExecutionContext(
            sessionID: sessionID,
            toolCallID: UUID().uuidString,
            parentToolCallID: nil,
            turnNumber: turnNumber,
            traceID: traceID ?? UUID().uuidString,
            tags: [:],
            permissionLevel: .standard
        )
    }
}
