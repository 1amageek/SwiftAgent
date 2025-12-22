//
//  AgentSession.swift
//  SwiftAgent
//
//  Created by SwiftAgent on 2025/01/15.
//

import Foundation
import OpenFoundationModels

/// An agent session that manages conversations and tool execution.
///
/// `AgentSession` is the main interface for interacting with an AI agent.
/// It handles prompt execution, tool calls, subagent delegation, and session persistence.
/// This is equivalent to the session management in Claude Agent SDK.
///
/// ## Usage
///
/// ```swift
/// // Create a session
/// let session = try await AgentSession.create(configuration: config)
///
/// // Send a prompt
/// let response = try await session.prompt("Hello!")
///
/// // Stream a response
/// let stream = session.stream("Write a function...")
/// for try await snapshot in stream {
///     print(snapshot.content)
/// }
///
/// // Fork the session
/// let forkedSession = try await session.fork()
/// ```
public actor AgentSession: Identifiable {

    // MARK: - Properties

    /// Unique identifier for this session.
    public nonisolated let id: String

    /// The session configuration.
    public let configuration: AgentConfiguration

    /// The underlying language model session.
    private var languageModelSession: LanguageModelSession

    /// The subagent registry.
    private let subagentRegistry: SubagentRegistry

    /// The tool provider.
    private let toolProvider: ToolProvider

    /// Resolved tools for this session.
    private let tools: [any Tool]

    /// Whether the session is currently responding.
    public private(set) var isResponding: Bool = false

    /// The current transcript.
    public var transcript: Transcript {
        languageModelSession.transcript
    }

    /// When the session was created.
    public nonisolated let createdAt: Date

    /// Parent session ID (if forked).
    public nonisolated let parentSessionId: String?

    /// Tool call history.
    private var toolCallHistory: [ToolCallRecord] = []

    // MARK: - Initialization

    /// Creates a new agent session.
    ///
    /// Use `AgentSession.create(configuration:)` instead of calling this directly.
    private init(
        id: String,
        configuration: AgentConfiguration,
        languageModelSession: LanguageModelSession,
        subagentRegistry: SubagentRegistry,
        toolProvider: ToolProvider,
        tools: [any Tool],
        createdAt: Date,
        parentSessionId: String?
    ) {
        self.id = id
        self.configuration = configuration
        self.languageModelSession = languageModelSession
        self.subagentRegistry = subagentRegistry
        self.toolProvider = toolProvider
        self.tools = tools
        self.createdAt = createdAt
        self.parentSessionId = parentSessionId
    }

    // MARK: - Factory Methods

    /// Creates a new agent session.
    ///
    /// This is equivalent to `unstable_v2_createSession()` in Claude Agent SDK.
    ///
    /// - Parameter configuration: The session configuration.
    /// - Returns: A new agent session.
    /// - Throws: `AgentError` if creation fails.
    public static func create(
        configuration: AgentConfiguration
    ) async throws -> AgentSession {
        // Validate configuration
        try configuration.validate()

        // Load model
        let model = try await configuration.modelProvider.provideModel()

        // Create tool provider
        let toolProvider = DefaultToolProvider(
            workingDirectory: configuration.workingDirectory
        )

        // Resolve tools
        let tools = configuration.tools.resolve(using: toolProvider)

        // Create subagent registry
        let subagentRegistry = SubagentRegistry(
            definitions: configuration.subagents
        )

        // Build instructions with subagent info
        var instructionsText = configuration.instructions.description

        // Add subagent descriptions if any
        let subagentDescriptions = await subagentRegistry.generateSubagentDescriptions()
        if !subagentDescriptions.isEmpty {
            instructionsText += "\n\n" + subagentDescriptions
        }

        // Create language model session
        let languageModelSession = LanguageModelSession(
            model: model,
            tools: tools,
            instructions: Instructions(instructionsText)
        )

        return AgentSession(
            id: UUID().uuidString,
            configuration: configuration,
            languageModelSession: languageModelSession,
            subagentRegistry: subagentRegistry,
            toolProvider: toolProvider,
            tools: tools,
            createdAt: Date(),
            parentSessionId: nil
        )
    }

    /// Resumes an existing session from a snapshot.
    ///
    /// This is equivalent to `unstable_v2_resumeSession()` in Claude Agent SDK.
    ///
    /// - Parameters:
    ///   - snapshot: The session snapshot to resume from.
    ///   - configuration: Optional configuration override.
    /// - Returns: The resumed session.
    /// - Throws: `AgentError` if resumption fails.
    public static func resume(
        from snapshot: SessionSnapshot,
        configuration: AgentConfiguration? = nil
    ) async throws -> AgentSession {
        // We need a configuration to resume
        guard let config = configuration else {
            throw AgentError.invalidConfiguration(
                reason: "Configuration required to resume session"
            )
        }

        // Validate configuration
        try config.validate()

        // Load model
        let model = try await config.modelProvider.provideModel()

        // Create tool provider
        let toolProvider = DefaultToolProvider(
            workingDirectory: config.workingDirectory
        )

        // Resolve tools
        let tools = config.tools.resolve(using: toolProvider)

        // Create subagent registry
        let subagentRegistry = SubagentRegistry(
            definitions: config.subagents
        )

        // Create language model session with existing transcript
        let languageModelSession = LanguageModelSession(
            model: model,
            tools: tools,
            transcript: snapshot.transcript
        )

        return AgentSession(
            id: snapshot.id,
            configuration: config,
            languageModelSession: languageModelSession,
            subagentRegistry: subagentRegistry,
            toolProvider: toolProvider,
            tools: tools,
            createdAt: snapshot.createdAt,
            parentSessionId: snapshot.parentSessionId
        )
    }

    /// Resumes a session by ID from a store.
    ///
    /// - Parameters:
    ///   - id: The session ID.
    ///   - store: The session store.
    ///   - configuration: The configuration to use.
    /// - Returns: The resumed session.
    /// - Throws: `AgentError.sessionNotFound` if the session doesn't exist.
    public static func resume(
        id: String,
        from store: any SessionStore,
        configuration: AgentConfiguration
    ) async throws -> AgentSession {
        guard let snapshot = try await store.load(id: id) else {
            throw AgentError.sessionNotFound(id: id)
        }

        return try await resume(from: snapshot, configuration: configuration)
    }

    // MARK: - Prompt Execution

    /// Sends a prompt and returns the response.
    ///
    /// This is equivalent to `unstable_v2_prompt()` in Claude Agent SDK.
    ///
    /// - Parameters:
    ///   - text: The prompt text.
    ///   - options: Optional generation options.
    /// - Returns: The agent response.
    /// - Throws: `AgentError` if prompt execution fails.
    @discardableResult
    public func prompt(
        _ text: String,
        options: GenerationOptions? = nil
    ) async throws -> AgentResponse<String> {
        guard !isResponding else {
            throw AgentError.sessionBusy
        }

        isResponding = true
        defer { isResponding = false }

        let startTime = ContinuousClock.now
        var toolCalls: [ToolCallRecord] = []

        let response = try await languageModelSession.respond(
            to: text,
            options: options ?? configuration.modelConfiguration.toGenerationOptions()
        )

        // Extract tool calls from transcript
        toolCalls = extractToolCalls(from: Array(response.transcriptEntries))

        let duration = ContinuousClock.now - startTime

        // Auto-save if configured
        if configuration.autoSave, let store = configuration.sessionStore {
            try? await save(to: store)
        }

        // Record tool calls
        toolCallHistory.append(contentsOf: toolCalls)

        return AgentResponse(
            content: response.content,
            rawContent: response.rawContent,
            transcriptEntries: Array(response.transcriptEntries),
            toolCalls: toolCalls,
            duration: duration
        )
    }

    /// Sends a prompt and returns a structured response.
    ///
    /// - Parameters:
    ///   - text: The prompt text.
    ///   - type: The expected response type.
    ///   - options: Optional generation options.
    /// - Returns: The typed agent response.
    /// - Throws: `AgentError` if generation or decoding fails.
    @discardableResult
    public func prompt<T: Generable>(
        _ text: String,
        generating type: T.Type,
        options: GenerationOptions? = nil
    ) async throws -> AgentResponse<T> {
        guard !isResponding else {
            throw AgentError.sessionBusy
        }

        isResponding = true
        defer { isResponding = false }

        let startTime = ContinuousClock.now
        var toolCalls: [ToolCallRecord] = []

        let response = try await languageModelSession.respond(
            to: text,
            generating: type,
            options: options ?? configuration.modelConfiguration.toGenerationOptions()
        )

        // Extract tool calls from transcript
        toolCalls = extractToolCalls(from: Array(response.transcriptEntries))

        let duration = ContinuousClock.now - startTime

        // Auto-save if configured
        if configuration.autoSave, let store = configuration.sessionStore {
            try? await save(to: store)
        }

        // Record tool calls
        toolCallHistory.append(contentsOf: toolCalls)

        return AgentResponse(
            content: response.content,
            rawContent: response.rawContent,
            transcriptEntries: Array(response.transcriptEntries),
            toolCalls: toolCalls,
            duration: duration
        )
    }

    // MARK: - Streaming

    /// Streams a response to a prompt.
    ///
    /// - Parameters:
    ///   - text: The prompt text.
    ///   - options: Optional generation options.
    /// - Returns: A stream of response snapshots.
    public func stream(
        _ text: String,
        options: GenerationOptions? = nil
    ) -> AgentResponseStream<String> {
        return AgentResponseStream<String>.create { [weak self] continuation in
            guard let self = self else {
                continuation.finish()
                return
            }

            do {
                let stream = await self.languageModelSession.streamResponse(
                    to: text,
                    options: options ?? self.configuration.modelConfiguration.toGenerationOptions()
                )

                let toolCalls: [ToolCallRecord] = []

                for try await snapshot in stream {
                    let agentSnapshot = AgentResponseStream<String>.Snapshot(
                        content: snapshot.content,
                        rawContent: snapshot.rawContent,
                        toolCalls: toolCalls,
                        isComplete: false
                    )
                    continuation.yield(agentSnapshot)
                }

                // Yield final snapshot
                continuation.finish()

            } catch {
                continuation.finish(throwing: error)
            }
        }
    }

    // MARK: - Subagent Delegation

    /// Invokes a subagent with a prompt.
    ///
    /// - Parameters:
    ///   - name: The name of the subagent.
    ///   - prompt: The prompt for the subagent.
    /// - Returns: The subagent's response.
    /// - Throws: `AgentError.subagentNotFound` if the subagent doesn't exist.
    public func invokeSubagent(
        _ name: String,
        prompt: String
    ) async throws -> AgentResponse<String> {
        let context = SubagentInvocationContext(
            parentModelProvider: configuration.modelProvider,
            parentTools: tools,
            toolProvider: toolProvider,
            workingDirectory: configuration.workingDirectory
        )

        return try await subagentRegistry.invoke(
            name,
            prompt: prompt,
            context: context
        )
    }

    /// Lists available subagents.
    public func listSubagents() async -> [SubagentDefinition] {
        await subagentRegistry.allDefinitions
    }

    // MARK: - Session Management

    /// Forks this session, creating a new branch.
    ///
    /// This is equivalent to using `forkSession` in Claude Agent SDK.
    ///
    /// - Returns: A new session forked from this one.
    /// - Throws: `AgentError` if forking fails.
    public func fork() async throws -> AgentSession {
        // Create a snapshot of current state
        let snapshot = SessionSnapshot(
            id: UUID().uuidString,
            transcript: transcript,
            createdAt: Date(),
            parentSessionId: id
        )

        // Resume from snapshot with same configuration
        return try await AgentSession.resume(
            from: snapshot,
            configuration: configuration
        )
    }

    /// Saves the session to a store.
    ///
    /// - Parameter store: The session store.
    /// - Throws: `AgentError.sessionSaveFailed` if saving fails.
    public func save(to store: any SessionStore) async throws {
        let snapshot = SessionSnapshot(
            id: id,
            transcript: transcript,
            createdAt: createdAt,
            updatedAt: Date(),
            parentSessionId: parentSessionId
        )

        do {
            try await store.save(snapshot)
        } catch {
            throw AgentError.sessionSaveFailed(underlyingError: error)
        }
    }

    /// Creates a snapshot of the current session state.
    public func snapshot() -> SessionSnapshot {
        SessionSnapshot(
            id: id,
            transcript: transcript,
            createdAt: createdAt,
            updatedAt: Date(),
            parentSessionId: parentSessionId
        )
    }

    // MARK: - History

    /// Gets the complete tool call history.
    public var allToolCalls: [ToolCallRecord] {
        toolCallHistory
    }

    /// Clears the tool call history.
    public func clearToolCallHistory() {
        toolCallHistory.removeAll()
    }

    // MARK: - Private Methods

    private func extractToolCalls(from entries: [Transcript.Entry]) -> [ToolCallRecord] {
        Transcript.extractToolCalls(from: entries)
    }
}

// MARK: - Convenience Extensions

extension AgentSession {

    /// Sends multiple prompts in sequence.
    ///
    /// - Parameter prompts: The prompts to send.
    /// - Returns: Array of responses.
    public func prompt(sequence prompts: [String]) async throws -> [AgentResponse<String>] {
        var responses: [AgentResponse<String>] = []
        for promptText in prompts {
            let response = try await prompt(promptText)
            responses.append(response)
        }
        return responses
    }

    /// Sends a prompt using a builder.
    @discardableResult
    public func prompt(
        options: GenerationOptions? = nil,
        @PromptBuilder builder: () throws -> Prompt
    ) async throws -> AgentResponse<String> {
        let prompt = try builder()
        return try await self.prompt(prompt.description, options: options)
    }
}
