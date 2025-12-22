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
    public nonisolated let parentSessionID: String?

    /// Tool call history.
    private var toolCallHistory: [ToolCallRecord] = []

    /// The tool execution pipeline.
    private let pipeline: ToolExecutionPipeline?

    /// The tool context store for tracking tool calls per turn.
    private let contextStore: ToolContextStore?

    /// The skill registry for managing agent skills.
    private let skillRegistry: SkillRegistry?

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
        pipeline: ToolExecutionPipeline?,
        contextStore: ToolContextStore?,
        skillRegistry: SkillRegistry?,
        createdAt: Date,
        parentSessionID: String?
    ) {
        self.id = id
        self.configuration = configuration
        self.languageModelSession = languageModelSession
        self.subagentRegistry = subagentRegistry
        self.toolProvider = toolProvider
        self.tools = tools
        self.pipeline = pipeline
        self.contextStore = contextStore
        self.skillRegistry = skillRegistry
        self.createdAt = createdAt
        self.parentSessionID = parentSessionID
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
        let resolvedTools = configuration.tools.resolve(using: toolProvider)

        // Create subagent registry
        let subagentRegistry = SubagentRegistry(
            definitions: configuration.subagents
        )

        // Initialize skill registry if configured
        let skillRegistry: SkillRegistry?
        if let skillsConfig = configuration.skills {
            // Use provided registry or create new one
            let registry = skillsConfig.registry ?? SkillRegistry()

            // Auto-discover skills if enabled
            if skillsConfig.autoDiscover {
                let discoveredSkills = try SkillDiscovery.discoverAll()
                await registry.register(discoveredSkills)

                // Discover from additional paths
                for path in skillsConfig.searchPaths {
                    let skills = try SkillDiscovery.discover(in: path)
                    await registry.register(skills)
                }
            }

            skillRegistry = registry
        } else {
            skillRegistry = nil
        }

        // Build instructions with subagent info
        var instructionsText = configuration.instructions.description

        // Add subagent descriptions if any
        let subagentDescriptions = await subagentRegistry.generateSubagentDescriptions()
        if !subagentDescriptions.isEmpty {
            instructionsText += "\n\n" + subagentDescriptions
        }

        // Add available skills prompt if any
        if let registry = skillRegistry {
            let skillsPrompt = await registry.generateAvailableSkillsPrompt()
            if !skillsPrompt.isEmpty {
                instructionsText += "\n\n" + skillsPrompt
            }
        }

        // Generate a single session ID to be shared
        let sessionID = UUID().uuidString

        // Add SkillTool if skills are enabled
        var allTools: [any Tool] = resolvedTools
        if let registry = skillRegistry {
            allTools.append(SkillTool(registry: registry))
        }

        // Create pipeline if there are hooks, permission delegate, or custom options
        let advancedOptions = configuration.pipelineConfiguration
        let hasPipelineConfig = !advancedOptions.globalHooks.isEmpty
            || advancedOptions.permissionDelegate != nil
            || !advancedOptions.toolOptions.isEmpty
            || advancedOptions.defaultRetry != nil

        let pipeline: ToolExecutionPipeline?
        let contextStore: ToolContextStore?
        let toolsForSession: [any Tool]

        if hasPipelineConfig {
            // Create pipeline
            pipeline = ToolExecutionPipeline(options: advancedOptions)

            // Create a context store to track tool calls per turn
            let store = ToolContextStore(
                sessionID: sessionID,
                maxPermissionLevel: advancedOptions.maxPermissionLevel
            )
            contextStore = store

            // Wrap tools with pipeline, recording each tool call
            toolsForSession = allTools.wrapped(
                with: pipeline!,
                contextProvider: { [store] in
                    await store.createContext()
                },
                onToolExecuted: { [store] toolName in
                    await store.recordToolCall(toolName)
                }
            )
        } else {
            pipeline = nil
            contextStore = nil
            toolsForSession = allTools
        }

        // Create language model session
        let languageModelSession = LanguageModelSession(
            model: model,
            tools: toolsForSession,
            instructions: Instructions(instructionsText)
        )

        return AgentSession(
            id: sessionID,
            configuration: configuration,
            languageModelSession: languageModelSession,
            subagentRegistry: subagentRegistry,
            toolProvider: toolProvider,
            tools: resolvedTools,
            pipeline: pipeline,
            contextStore: contextStore,
            skillRegistry: skillRegistry,
            createdAt: Date(),
            parentSessionID: nil
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
        let resolvedTools = config.tools.resolve(using: toolProvider)

        // Create subagent registry
        let subagentRegistry = SubagentRegistry(
            definitions: config.subagents
        )

        // Initialize skill registry if configured
        let skillRegistry: SkillRegistry?
        if let skillsConfig = config.skills {
            let registry = skillsConfig.registry ?? SkillRegistry()
            if skillsConfig.autoDiscover {
                let discoveredSkills = try SkillDiscovery.discoverAll()
                await registry.register(discoveredSkills)
                for path in skillsConfig.searchPaths {
                    let skills = try SkillDiscovery.discover(in: path)
                    await registry.register(skills)
                }
            }
            skillRegistry = registry
        } else {
            skillRegistry = nil
        }

        // Add SkillTool if skills are enabled
        var allTools: [any Tool] = resolvedTools
        if let registry = skillRegistry {
            allTools.append(SkillTool(registry: registry))
        }

        // Create pipeline if configured
        let advancedOptions = config.pipelineConfiguration
        let hasPipelineConfig = !advancedOptions.globalHooks.isEmpty
            || advancedOptions.permissionDelegate != nil
            || !advancedOptions.toolOptions.isEmpty
            || advancedOptions.defaultRetry != nil

        let pipeline: ToolExecutionPipeline?
        let contextStore: ToolContextStore?
        let toolsForSession: [any Tool]

        if hasPipelineConfig {
            pipeline = ToolExecutionPipeline(options: advancedOptions)
            let store = ToolContextStore(
                sessionID: snapshot.id,
                maxPermissionLevel: advancedOptions.maxPermissionLevel
            )
            contextStore = store
            toolsForSession = allTools.wrapped(
                with: pipeline!,
                contextProvider: { [store] in
                    await store.createContext()
                },
                onToolExecuted: { [store] toolName in
                    await store.recordToolCall(toolName)
                }
            )
        } else {
            pipeline = nil
            contextStore = nil
            toolsForSession = allTools
        }

        // Create language model session with existing transcript
        let languageModelSession = LanguageModelSession(
            model: model,
            tools: toolsForSession,
            transcript: snapshot.transcript
        )

        return AgentSession(
            id: snapshot.id,
            configuration: config,
            languageModelSession: languageModelSession,
            subagentRegistry: subagentRegistry,
            toolProvider: toolProvider,
            tools: resolvedTools,
            pipeline: pipeline,
            contextStore: contextStore,
            skillRegistry: skillRegistry,
            createdAt: snapshot.createdAt,
            parentSessionID: snapshot.parentSessionID
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

        // Start a new turn for context tracking
        await contextStore?.startNewTurn()

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

        // Start a new turn for context tracking
        await contextStore?.startNewTurn()

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
    /// - Throws: `AgentError.sessionBusy` if the session is already responding.
    public func stream(
        _ text: String,
        options: GenerationOptions? = nil
    ) async throws -> AgentResponseStream<String> {
        guard !isResponding else {
            throw AgentError.sessionBusy
        }

        isResponding = true

        // Start a new turn for context tracking
        await contextStore?.startNewTurn()

        // Capture necessary state for the stream closure
        let languageModelSession = self.languageModelSession
        let generationOptions = options ?? configuration.modelConfiguration.toGenerationOptions()
        let autoSave = configuration.autoSave
        let sessionStore = configuration.sessionStore

        return AgentResponseStream<String>.create { [weak self] continuation in
            do {
                let stream = languageModelSession.streamResponse(
                    to: text,
                    options: generationOptions
                )

                var toolCalls: [ToolCallRecord] = []

                for try await snapshot in stream {
                    let agentSnapshot = AgentResponseStream<String>.Snapshot(
                        content: snapshot.content,
                        rawContent: snapshot.rawContent,
                        toolCalls: toolCalls,
                        isComplete: false
                    )
                    continuation.yield(agentSnapshot)
                }

                // Extract tool calls from final transcript after stream completes
                if let self = self {
                    let transcriptEntries = await self.getCurrentTranscriptEntries()
                    toolCalls = Transcript.extractToolCalls(from: transcriptEntries)

                    await self.finishStream(
                        toolCalls: toolCalls,
                        autoSave: autoSave,
                        sessionStore: sessionStore
                    )
                }

                continuation.finish()

            } catch {
                // Reset responding state on error
                if let self = self {
                    await self.resetRespondingState()
                }
                continuation.finish(throwing: error)
            }
        }
    }

    /// Gets the current transcript entries.
    private func getCurrentTranscriptEntries() -> [Transcript.Entry] {
        Array(transcript)
    }

    /// Finishes a streaming response by updating session state.
    private func finishStream(
        toolCalls: [ToolCallRecord],
        autoSave: Bool,
        sessionStore: (any SessionStore)?
    ) async {
        isResponding = false
        toolCallHistory.append(contentsOf: toolCalls)

        // Auto-save if configured
        if autoSave, let store = sessionStore {
            try? await save(to: store)
        }
    }

    /// Resets the responding state on error.
    private func resetRespondingState() {
        isResponding = false
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

    // MARK: - Skills

    /// Lists available skills.
    ///
    /// Returns all skills that have been discovered and registered.
    public func listSkills() async -> [Skill] {
        guard let registry = skillRegistry else { return [] }
        return await registry.allSkills
    }

    /// Activates a skill by name.
    ///
    /// This loads the skill's full instructions into memory.
    ///
    /// - Parameter name: The skill name.
    /// - Returns: The activated skill with full instructions.
    /// - Throws: `SkillError.skillNotFound` if skill doesn't exist.
    public func activateSkill(_ name: String) async throws -> Skill {
        guard let registry = skillRegistry else {
            throw SkillError.skillNotFound(name: name)
        }
        return try await registry.activate(name)
    }

    /// Deactivates a skill.
    ///
    /// - Parameter name: The skill name.
    public func deactivateSkill(_ name: String) async {
        await skillRegistry?.deactivate(name)
    }

    /// Gets currently active skill names.
    public func activeSkillNames() async -> [String] {
        guard let registry = skillRegistry else { return [] }
        return await registry.activeSkillNames
    }

    /// Checks if skills are enabled for this session.
    public var skillsEnabled: Bool {
        skillRegistry != nil
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
            parentSessionID: id
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
            parentSessionID: parentSessionID
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
            parentSessionID: parentSessionID
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

// MARK: - File Checkpointing

/// Global storage for checkpoint managers, keyed by session ID.
private actor CheckpointManagerStore {
    static let shared = CheckpointManagerStore()

    private var managers: [String: CheckpointManager] = [:]

    func manager(for sessionID: String) -> CheckpointManager {
        if let existing = managers[sessionID] {
            return existing
        }
        let manager = CheckpointManager()
        managers[sessionID] = manager
        return manager
    }

    func remove(for sessionID: String) {
        managers.removeValue(forKey: sessionID)
    }
}

extension AgentSession {

    /// The checkpoint manager for this session.
    ///
    /// Use this to create and manage file checkpoints.
    public var checkpointManager: CheckpointManager {
        get async {
            await CheckpointManagerStore.shared.manager(for: id)
        }
    }

    /// Adds a file or directory to the checkpoint tracking list.
    ///
    /// Tracked files will be included when creating checkpoints.
    ///
    /// - Parameter path: The path to track. Can be a file or directory.
    /// - Throws: `CheckpointError.pathNotFound` if the path doesn't exist.
    public func trackFile(_ path: String) async throws {
        try await checkpointManager.track(path)
    }

    /// Adds multiple files or directories to the checkpoint tracking list.
    ///
    /// - Parameter paths: The paths to track.
    /// - Throws: `CheckpointError.pathNotFound` if any path doesn't exist.
    public func trackFiles(_ paths: [String]) async throws {
        for path in paths {
            try await checkpointManager.track(path)
        }
    }

    /// Removes a path from checkpoint tracking.
    ///
    /// - Parameter path: The path to stop tracking.
    public func untrackFile(_ path: String) async {
        await checkpointManager.untrack(path)
    }

    /// Creates a checkpoint of all tracked files.
    ///
    /// Use this to save the current state of tracked files before making changes.
    ///
    /// - Parameters:
    ///   - name: A human-readable name for this checkpoint.
    ///   - metadata: Optional custom metadata to associate with the checkpoint.
    /// - Returns: Information about the created checkpoint.
    ///
    /// ## Example
    ///
    /// ```swift
    /// let session = try await AgentSession.create(configuration: config)
    ///
    /// // Track files
    /// try await session.trackFile("/path/to/project/src")
    ///
    /// // Create checkpoint before changes
    /// let checkpoint = try await session.checkpoint("before-refactoring")
    ///
    /// // ... LLM makes changes ...
    ///
    /// // Rewind if needed
    /// try await session.rewind(to: checkpoint.id)
    /// ```
    @discardableResult
    public func checkpoint(
        _ name: String,
        metadata: [String: String] = [:]
    ) async throws -> CheckpointManager.CheckpointInfo {
        try await checkpointManager.createCheckpoint(name: name, metadata: metadata)
    }

    /// Returns all checkpoints for this session.
    ///
    /// - Returns: Array of checkpoint info, sorted by creation time.
    public func listCheckpoints() async -> [CheckpointManager.CheckpointInfo] {
        await checkpointManager.listCheckpoints()
    }

    /// Gets a checkpoint by its ID.
    ///
    /// - Parameter id: The checkpoint ID.
    /// - Returns: The checkpoint info, or nil if not found.
    public func getCheckpoint(_ id: String) async -> CheckpointManager.CheckpointInfo? {
        await checkpointManager.getCheckpoint(id)
    }

    /// Gets a checkpoint by its name.
    ///
    /// - Parameter name: The checkpoint name.
    /// - Returns: The most recent checkpoint with that name, or nil if not found.
    public func getCheckpoint(named name: String) async -> CheckpointManager.CheckpointInfo? {
        await checkpointManager.getCheckpoint(named: name)
    }

    /// Restores all tracked files to their state at a checkpoint.
    ///
    /// This reverts any changes made to tracked files since the checkpoint was created.
    ///
    /// - Parameter checkpointID: The ID of the checkpoint to restore.
    /// - Returns: Array of paths that were restored.
    /// - Throws: `CheckpointError.checkpointNotFound` if the checkpoint doesn't exist.
    @discardableResult
    public func rewind(to checkpointID: String) async throws -> [String] {
        try await checkpointManager.rewind(to: checkpointID)
    }

    /// Restores a specific file to its state at a checkpoint.
    ///
    /// - Parameters:
    ///   - path: The path of the file to restore.
    ///   - checkpointID: The ID of the checkpoint.
    /// - Throws: `CheckpointError` if the checkpoint or file is not found.
    public func rewindFile(_ path: String, to checkpointID: String) async throws {
        try await checkpointManager.rewindFile(path, to: checkpointID)
    }

    /// Compares current file states with a checkpoint.
    ///
    /// - Parameter checkpointID: The ID of the checkpoint to compare against.
    /// - Returns: A diff showing which files changed, were added, or were deleted.
    /// - Throws: `CheckpointError.checkpointNotFound` if the checkpoint doesn't exist.
    public func diff(from checkpointID: String) async throws -> CheckpointDiff {
        try await checkpointManager.diff(from: checkpointID)
    }

    /// Deletes a checkpoint.
    ///
    /// - Parameter id: The ID of the checkpoint to delete.
    /// - Returns: The deleted checkpoint info, or nil if not found.
    @discardableResult
    public func deleteCheckpoint(_ id: String) async -> CheckpointManager.CheckpointInfo? {
        await checkpointManager.deleteCheckpoint(id)
    }

    /// Deletes all checkpoints for this session.
    public func clearAllCheckpoints() async {
        await checkpointManager.clearAllCheckpoints()
    }
}
