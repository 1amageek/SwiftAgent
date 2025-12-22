//
//  HookEvent.swift
//  SwiftAgent
//
//  Created by SwiftAgent on 2025/01/23.
//

import Foundation

/// Events that can trigger hook execution.
///
/// Hooks can be registered to execute at various points in the agent lifecycle,
/// providing opportunities to validate, modify, log, or block operations.
///
/// ## Event Categories
///
/// ### Tool Execution Events
/// - `preToolUse`: Before a tool is executed
/// - `postToolUse`: After a tool completes successfully
///
/// ### Permission Events
/// - `permissionRequest`: When permission dialog would be shown
///
/// ### User Interaction Events
/// - `userPromptSubmit`: When user submits a prompt
/// - `notification`: When a notification is sent
///
/// ### Agent Control Events
/// - `stop`: When deciding if agent should stop
/// - `subagentStop`: When deciding if subagent should stop
///
/// ### Session Lifecycle Events
/// - `sessionStart`: When a session begins
/// - `sessionEnd`: When a session ends
/// - `preCompact`: Before context compaction
public enum HookEvent: String, Codable, Sendable, CaseIterable {

    // MARK: - Tool Execution Events

    /// Fires before a tool is executed.
    ///
    /// Use this hook to:
    /// - Validate tool inputs
    /// - Modify arguments
    /// - Block dangerous operations
    /// - Log tool usage
    ///
    /// The hook can return decisions to allow, deny, ask, or modify input.
    case preToolUse

    /// Fires after a tool executes successfully.
    ///
    /// Use this hook to:
    /// - Log results
    /// - Validate outputs
    /// - Trigger side effects (e.g., run formatters)
    /// - Collect metrics
    case postToolUse

    // MARK: - Permission Events

    /// Fires when a permission dialog would be shown.
    ///
    /// Use this hook to:
    /// - Automatically approve/deny based on context
    /// - Log permission requests
    /// - Implement custom approval UI
    case permissionRequest

    // MARK: - User Interaction Events

    /// Fires when user submits a prompt.
    ///
    /// Use this hook to:
    /// - Validate user input
    /// - Add context to prompts
    /// - Block sensitive prompts
    /// - Transform user messages
    case userPromptSubmit

    /// Fires when a notification is sent.
    ///
    /// Use this hook to:
    /// - Custom notification handling
    /// - Desktop notifications
    /// - Logging
    case notification

    // MARK: - Agent Control Events

    /// Fires when deciding if agent should stop responding.
    ///
    /// Use this hook to:
    /// - Evaluate task completion
    /// - Force continuation
    /// - Add follow-up prompts
    case stop

    /// Fires when a subagent completes.
    ///
    /// Use this hook to:
    /// - Evaluate subagent results
    /// - Decide if subagent should continue
    /// - Aggregate results
    case subagentStop

    // MARK: - Session Lifecycle Events

    /// Fires when a session begins or resumes.
    ///
    /// Use this hook to:
    /// - Load project context
    /// - Install dependencies
    /// - Set environment variables
    /// - Initialize resources
    case sessionStart

    /// Fires when a session ends.
    ///
    /// Use this hook to:
    /// - Cleanup resources
    /// - Save state
    /// - Log session summary
    case sessionEnd

    /// Fires before context compaction.
    ///
    /// Use this hook to:
    /// - Run pre-compaction tasks
    /// - Save important context
    /// - Log compaction events
    case preCompact
}

// MARK: - Properties

extension HookEvent {

    /// A description of this event.
    public var description: String {
        switch self {
        case .preToolUse:
            return "Before tool execution"
        case .postToolUse:
            return "After tool execution"
        case .permissionRequest:
            return "Permission dialog shown"
        case .userPromptSubmit:
            return "User prompt submitted"
        case .notification:
            return "Notification sent"
        case .stop:
            return "Agent stop decision"
        case .subagentStop:
            return "Subagent stop decision"
        case .sessionStart:
            return "Session started"
        case .sessionEnd:
            return "Session ended"
        case .preCompact:
            return "Before context compaction"
        }
    }

    /// Whether this event is related to tool execution.
    public var isToolEvent: Bool {
        switch self {
        case .preToolUse, .postToolUse:
            return true
        default:
            return false
        }
    }

    /// Whether this event fires once per session.
    public var isSessionEvent: Bool {
        switch self {
        case .sessionStart, .sessionEnd:
            return true
        default:
            return false
        }
    }

    /// Whether this event can block execution.
    public var canBlock: Bool {
        switch self {
        case .preToolUse, .permissionRequest, .userPromptSubmit, .stop, .subagentStop:
            return true
        default:
            return false
        }
    }
}
