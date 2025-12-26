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

    /// The tool provider.
    private let toolProvider: ToolProvider

    /// Resolved tools for this session.
    private let tools: [any Tool]

    /// Tools configured for the language model session (may include wrappers).
    private let sessionTools: [any Tool]

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


    /// The skill registry for managing agent skills.
    private let skillRegistry: SkillRegistry?

    /// The context manager for token tracking and compaction.
    private let contextManager: ContextManager?

    // MARK: - Initialization

    /// Creates a new agent session.
    ///
    /// Use `AgentSession.create(configuration:)` instead of calling this directly.
    private init(
        id: String,
        configuration: AgentConfiguration,
        languageModelSession: LanguageModelSession,
        toolProvider: ToolProvider,
        tools: [any Tool],
        sessionTools: [any Tool],
        skillRegistry: SkillRegistry?,
        contextManager: ContextManager?,
        createdAt: Date,
        parentSessionID: String?
    ) {
        self.id = id
        self.configuration = configuration
        self.languageModelSession = languageModelSession
        self.toolProvider = toolProvider
        self.tools = tools
        self.sessionTools = sessionTools
        self.skillRegistry = skillRegistry
        self.contextManager = contextManager
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

        // Build instructions
        var instructionsText = configuration.instructions.description

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

        // Wrap tools with middleware pipeline if configured
        let toolsForSession: [any Tool]
        if let toolPipeline = configuration.toolPipeline {
            toolsForSession = toolPipeline.wrap(allTools)
        } else {
            toolsForSession = allTools
        }

        // Create language model session
        let languageModelSession = LanguageModelSession(
            model: model,
            tools: toolsForSession,
            instructions: Instructions(instructionsText)
        )

        // Create context manager if configured
        let contextManager: ContextManager?
        if let contextConfig = configuration.context, contextConfig.enabled {
            contextManager = ContextManager(configuration: contextConfig)
        } else {
            contextManager = nil
        }

        return AgentSession(
            id: sessionID,
            configuration: configuration,
            languageModelSession: languageModelSession,
            toolProvider: toolProvider,
            tools: resolvedTools,
            sessionTools: toolsForSession,
            skillRegistry: skillRegistry,
            contextManager: contextManager,
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

        // Wrap tools with middleware pipeline if configured
        let toolsForSession: [any Tool]
        if let toolPipeline = config.toolPipeline {
            toolsForSession = toolPipeline.wrap(allTools)
        } else {
            toolsForSession = allTools
        }

        // Create language model session with existing transcript
        let languageModelSession = LanguageModelSession(
            model: model,
            tools: toolsForSession,
            transcript: snapshot.transcript
        )

        // Create context manager if configured
        let contextManager: ContextManager?
        if let contextConfig = config.context, contextConfig.enabled {
            contextManager = ContextManager(configuration: contextConfig)
        } else {
            contextManager = nil
        }

        return AgentSession(
            id: snapshot.id,
            configuration: config,
            languageModelSession: languageModelSession,
            toolProvider: toolProvider,
            tools: resolvedTools,
            sessionTools: toolsForSession,
            skillRegistry: skillRegistry,
            contextManager: contextManager,
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

        // Auto-compact if enabled and threshold exceeded
        try await performAutoCompactIfNeeded()

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

        // Auto-compact if enabled and threshold exceeded
        try await performAutoCompactIfNeeded()

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

        // Auto-compact if enabled and threshold exceeded (before capturing session)
        try await performAutoCompactIfNeeded()

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

// MARK: - Context Management

extension AgentSession {

    /// Whether context management is enabled for this session.
    public var contextManagementEnabled: Bool {
        contextManager != nil
    }

    /// Gets current context usage statistics.
    ///
    /// Returns `nil` if context management is disabled.
    ///
    /// ## Example
    ///
    /// ```swift
    /// if let usage = await session.contextUsage() {
    ///     print("Using \(usage.usagePercentage)% of context")
    ///     if usage.isAboveWarningThreshold() {
    ///         print("Warning: Context is getting full")
    ///     }
    /// }
    /// ```
    public func contextUsage() async -> ContextUsage? {
        guard let manager = contextManager else { return nil }
        return await manager.calculateUsage(for: transcript)
    }

    /// Checks if context compaction is needed.
    ///
    /// - Returns: `true` if usage exceeds the compaction threshold.
    public func needsCompaction() async -> Bool {
        guard let manager = contextManager else { return false }
        return await manager.needsCompaction(for: transcript)
    }

    /// Checks if context usage is at warning level.
    ///
    /// - Returns: `true` if usage exceeds the warning threshold but not compaction threshold.
    public func isContextAtWarningLevel() async -> Bool {
        guard let manager = contextManager else { return false }
        return await manager.isAtWarningLevel(for: transcript)
    }

    /// Manually triggers context compaction.
    ///
    /// This forces compaction regardless of the current usage level.
    /// If context management is disabled, returns `nil`.
    ///
    /// ## Example
    ///
    /// ```swift
    /// if let result = try await session.compactContext() {
    ///     print("Compaction saved \(result.tokensSaved) tokens")
    ///     print("Removed \(result.entriesRemoved) entries")
    /// }
    /// ```
    ///
    /// - Returns: The compaction result, or `nil` if context management is disabled.
    /// - Throws: `CompactionError` if compaction fails.
    public func compactContext() async throws -> ContextManager.CompactionResult? {
        guard let manager = contextManager else { return nil }

        let (compactedEntries, result) = try await manager.compactIfNeeded(
            transcript: transcript,
            sessionID: id
        )

        // Apply compacted entries if compaction was performed
        if result.wasCompacted {
            try await applyCompactedTranscript(entries: compactedEntries)
        }

        return result
    }

    /// Performs auto-compaction if enabled and threshold exceeded.
    ///
    /// This is called before each prompt/stream to ensure context stays within limits.
    private func performAutoCompactIfNeeded() async throws {
        guard let contextConfig = configuration.context,
              contextConfig.enabled,
              contextConfig.autoCompact,
              let manager = contextManager else {
            return
        }

        let (compactedEntries, result) = try await manager.compactIfNeeded(
            transcript: transcript,
            sessionID: id
        )

        if result.wasCompacted {
            try await applyCompactedTranscript(entries: compactedEntries)
        }
    }

    /// Applies compacted entries by recreating the language model session.
    private func applyCompactedTranscript(entries: [Transcript.Entry]) async throws {
        // Create a new transcript from compacted entries
        let compactedTranscript = Transcript(entries: entries)

        // Get the model
        let model = try await configuration.modelProvider.provideModel()

        // Create new language model session with compacted transcript
        languageModelSession = LanguageModelSession(
            model: model,
            tools: sessionTools,
            transcript: compactedTranscript
        )
    }

    /// Marks an entry as preserved during compaction.
    ///
    /// Preserved entries will not be removed or summarized during automatic
    /// or manual compaction.
    ///
    /// - Parameter index: The entry index to preserve.
    public func preserveEntry(at index: Int) async {
        await contextManager?.preserveEntry(at: index)
    }

    /// Removes preservation for an entry.
    ///
    /// - Parameter index: The entry index to unpreserve.
    public func unpreserveEntry(at index: Int) async {
        await contextManager?.unpreserveEntry(at: index)
    }

    /// Clears all preserved entries.
    public func clearPreservedEntries() async {
        await contextManager?.clearPreservedEntries()
    }

    /// Gets compaction statistics for this session.
    ///
    /// Returns `nil` if context management is disabled.
    public func contextStatistics() async -> ContextManager.Statistics? {
        await contextManager?.statistics
    }
}
