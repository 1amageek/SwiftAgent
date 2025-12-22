//
//  ToolContextStore.swift
//  SwiftAgent
//
//  Created by SwiftAgent on 2025/01/15.
//

import Foundation

/// An actor that manages tool execution context for a session.
///
/// This store tracks the current turn number and tool calls made within each turn,
/// providing the necessary context for permission decisions and hooks.
public actor ToolContextStore: Sendable {

    /// The session ID.
    public let sessionID: String

    /// The maximum permission level allowed for tools in this session.
    ///
    /// Tools with a higher permission level than this will be rejected.
    /// Defaults to `.standard`.
    private var maxPermissionLevel: ToolPermissionLevel

    /// The current turn number.
    private var turnNumber: Int = 0

    /// Tool calls made in the current turn.
    private var currentTurnToolCalls: [String] = []

    /// A unique trace ID for the current turn.
    private var currentTraceID: String = UUID().uuidString

    /// Creates a new context store.
    ///
    /// - Parameters:
    ///   - sessionID: The session ID.
    ///   - maxPermissionLevel: The maximum permission level allowed (default: .standard).
    public init(sessionID: String, maxPermissionLevel: ToolPermissionLevel = .standard) {
        self.sessionID = sessionID
        self.maxPermissionLevel = maxPermissionLevel
    }

    /// Sets the maximum permission level for this session.
    ///
    /// - Parameter level: The new maximum permission level.
    public func setMaxPermissionLevel(_ level: ToolPermissionLevel) {
        maxPermissionLevel = level
    }

    /// Gets the current maximum permission level.
    public var currentMaxPermissionLevel: ToolPermissionLevel {
        maxPermissionLevel
    }

    /// Increments the turn number and resets turn-specific tracking.
    ///
    /// Call this at the start of each new prompt.
    public func startNewTurn() {
        turnNumber += 1
        currentTurnToolCalls = []
        currentTraceID = UUID().uuidString
    }

    /// Records a tool call in the current turn.
    ///
    /// - Parameter toolName: The name of the tool that was called.
    public func recordToolCall(_ toolName: String) {
        currentTurnToolCalls.append(toolName)
    }

    /// Gets the tool calls made in the current turn.
    public var previousToolCalls: [String] {
        currentTurnToolCalls
    }

    /// Gets the current turn number.
    public var currentTurnNumber: Int {
        turnNumber
    }

    /// Creates a tool execution context with the current state.
    ///
    /// - Returns: A new execution context.
    public func createContext() -> ToolExecutionContext {
        ToolExecutionContext(
            sessionID: sessionID,
            toolCallID: UUID().uuidString,
            parentToolCallID: nil,
            turnNumber: turnNumber,
            traceID: currentTraceID,
            tags: [:],
            permissionLevel: maxPermissionLevel,
            previousToolCalls: currentTurnToolCalls
        )
    }

    /// Creates a permission context with the current state.
    ///
    /// - Returns: A new permission context.
    public func createPermissionContext() -> ToolPermissionContext {
        ToolPermissionContext(
            sessionID: sessionID,
            turnNumber: turnNumber,
            previousToolCalls: currentTurnToolCalls
        )
    }
}
