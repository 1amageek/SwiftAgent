//
//  HookContext.swift
//  SwiftAgent
//
//  Created by SwiftAgent on 2025/01/23.
//

import Foundation

/// Context information passed to hooks during execution.
///
/// `HookContext` provides all the information a hook needs to make decisions
/// or perform actions related to the current event.
public struct HookContext: Sendable {

    // MARK: - Common Properties

    /// The type of event that triggered this hook.
    public let event: HookEvent

    /// The session ID, if available.
    public let sessionID: String?

    /// The current working directory.
    public let workingDirectory: String

    /// The current permission mode.
    public let permissionMode: PermissionMode

    /// Timestamp when the event occurred.
    public let timestamp: Date

    // MARK: - Tool-Related Properties

    /// The name of the tool being used (for tool events).
    public let toolName: String?

    /// The tool's input arguments as JSON (for tool events).
    public let toolInput: String?

    /// The tool use ID (for tool events).
    public let toolUseID: String?

    /// The tool's output (for postToolUse).
    public let toolOutput: String?

    /// The execution duration (for postToolUse).
    public let executionDuration: Duration?

    // MARK: - User Prompt Properties

    /// The user's prompt text (for userPromptSubmit).
    public let userPrompt: String?

    // MARK: - Session Properties

    /// Whether this is a new session (for sessionStart).
    public let isNewSession: Bool?

    /// Path to the conversation transcript.
    public let transcriptPath: String?

    // MARK: - Trace Properties

    /// The trace ID for distributed tracing.
    public let traceID: String?

    /// The parent span ID.
    public let parentSpanID: String?

    // MARK: - Error Properties

    /// Error that occurred (if any).
    public let error: Error?

    // MARK: - Initializers

    /// Creates a new hook context.
    public init(
        event: HookEvent,
        sessionID: String? = nil,
        workingDirectory: String = FileManager.default.currentDirectoryPath,
        permissionMode: PermissionMode = .default,
        timestamp: Date = Date(),
        toolName: String? = nil,
        toolInput: String? = nil,
        toolUseID: String? = nil,
        toolOutput: String? = nil,
        executionDuration: Duration? = nil,
        userPrompt: String? = nil,
        isNewSession: Bool? = nil,
        transcriptPath: String? = nil,
        traceID: String? = nil,
        parentSpanID: String? = nil,
        error: Error? = nil
    ) {
        self.event = event
        self.sessionID = sessionID
        self.workingDirectory = workingDirectory
        self.permissionMode = permissionMode
        self.timestamp = timestamp
        self.toolName = toolName
        self.toolInput = toolInput
        self.toolUseID = toolUseID
        self.toolOutput = toolOutput
        self.executionDuration = executionDuration
        self.userPrompt = userPrompt
        self.isNewSession = isNewSession
        self.transcriptPath = transcriptPath
        self.traceID = traceID
        self.parentSpanID = parentSpanID
        self.error = error
    }
}

// MARK: - Convenience Factory Methods

extension HookContext {

    /// Creates a context for preToolUse event.
    public static func preToolUse(
        toolName: String,
        toolInput: String,
        toolUseID: String? = nil,
        sessionID: String? = nil,
        workingDirectory: String = FileManager.default.currentDirectoryPath,
        permissionMode: PermissionMode = .default,
        traceID: String? = nil
    ) -> HookContext {
        HookContext(
            event: .preToolUse,
            sessionID: sessionID,
            workingDirectory: workingDirectory,
            permissionMode: permissionMode,
            toolName: toolName,
            toolInput: toolInput,
            toolUseID: toolUseID,
            traceID: traceID
        )
    }

    /// Creates a context for postToolUse event.
    public static func postToolUse(
        toolName: String,
        toolInput: String,
        toolOutput: String,
        executionDuration: Duration,
        toolUseID: String? = nil,
        sessionID: String? = nil,
        workingDirectory: String = FileManager.default.currentDirectoryPath,
        permissionMode: PermissionMode = .default,
        traceID: String? = nil
    ) -> HookContext {
        HookContext(
            event: .postToolUse,
            sessionID: sessionID,
            workingDirectory: workingDirectory,
            permissionMode: permissionMode,
            toolName: toolName,
            toolInput: toolInput,
            toolUseID: toolUseID,
            toolOutput: toolOutput,
            executionDuration: executionDuration,
            traceID: traceID
        )
    }

    /// Creates a context for sessionStart event.
    public static func sessionStart(
        sessionID: String? = nil,
        isNewSession: Bool = true,
        workingDirectory: String = FileManager.default.currentDirectoryPath,
        transcriptPath: String? = nil
    ) -> HookContext {
        HookContext(
            event: .sessionStart,
            sessionID: sessionID,
            workingDirectory: workingDirectory,
            isNewSession: isNewSession,
            transcriptPath: transcriptPath
        )
    }

    /// Creates a context for sessionEnd event.
    public static func sessionEnd(
        sessionID: String? = nil,
        workingDirectory: String = FileManager.default.currentDirectoryPath,
        transcriptPath: String? = nil
    ) -> HookContext {
        HookContext(
            event: .sessionEnd,
            sessionID: sessionID,
            workingDirectory: workingDirectory,
            transcriptPath: transcriptPath
        )
    }

    /// Creates a context for userPromptSubmit event.
    public static func userPromptSubmit(
        prompt: String,
        sessionID: String? = nil,
        workingDirectory: String = FileManager.default.currentDirectoryPath
    ) -> HookContext {
        HookContext(
            event: .userPromptSubmit,
            sessionID: sessionID,
            workingDirectory: workingDirectory,
            userPrompt: prompt
        )
    }

    /// Creates a context for permissionRequest event.
    public static func permissionRequest(
        toolName: String,
        toolInput: String,
        sessionID: String? = nil,
        workingDirectory: String = FileManager.default.currentDirectoryPath,
        permissionMode: PermissionMode = .default
    ) -> HookContext {
        HookContext(
            event: .permissionRequest,
            sessionID: sessionID,
            workingDirectory: workingDirectory,
            permissionMode: permissionMode,
            toolName: toolName,
            toolInput: toolInput
        )
    }
}
