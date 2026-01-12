//
//  AgentSession.swift
//  SwiftAgent
//
//  Created by SwiftAgent on 2025/01/08.
//

import Foundation
import Synchronization

/// A thread-safe class that manages an interactive session with a language model.
///
/// `AgentSession` provides a simple interface for sending messages to a language model
/// and receiving responses. It supports steering where additional context can be
/// accumulated and included in subsequent prompts.
///
/// This is implemented as a class with Mutex (not actor) for compatibility with
/// distributed actors and other contexts where actor isolation is problematic.
///
/// ## Usage
///
/// ```swift
/// let session = AgentSession(tools: myTools) {
///     Instructions("You are a helpful assistant.")
/// }
///
/// let response = try await session.send("Hello!")
/// print(response.content)
/// ```
///
/// ## Steering
///
/// Use `steer()` to add additional context to the **next** prompt:
///
/// ```swift
/// // Add steering hints before sending
/// session.steer("Make sure to use async/await")
/// session.steer("Add error handling")
///
/// // Steering messages are combined with the next send()
/// let response = try await session.send("Write a function...")
/// print(response.content)
/// ```
///
/// **Note:** Steering messages added while a prompt is being processed
/// will be included in the *following* prompt, not the current one.
///
/// ## Event Integration
///
/// AgentSession automatically emits events through its EventBus:
///
/// ```swift
/// let eventBus = EventBus()
/// await eventBus.on(.promptSubmitted) { event in
///     if let sessionEvent = event as? SessionEvent {
///         print("Session \(sessionEvent.sessionID) received prompt")
///     }
/// }
///
/// let session = AgentSession(eventBus: eventBus, tools: myTools) {
///     Instructions("You are a helpful assistant.")
/// }
/// ```
///
/// ## Persistence
///
/// Sessions can be saved and restored using `SessionSnapshot`:
///
/// ```swift
/// // Save
/// let snapshot = session.snapshot()
/// try await store.save(snapshot)
///
/// // Restore
/// if let snapshot = try await store.load(id: sessionID) {
///     let restored = AgentSession.restore(from: snapshot, tools: myTools)
/// }
/// ```

/// Delegate protocol for creating and managing LanguageModelSession instances.
///
/// This delegate allows AgentSession to recreate its underlying LanguageModelSession
/// when needed (e.g., for transcript compaction) without knowing the specific
/// model configuration details.
public protocol LanguageModelSessionDelegate: Sendable {
    /// Creates a new LanguageModelSession with the given transcript.
    ///
    /// - Parameter transcript: The transcript to initialize the session with.
    /// - Returns: A new LanguageModelSession instance.
    func createSession(with transcript: Transcript) -> LanguageModelSession
}

/// Default delegate implementation that uses a factory closure to create sessions.
///
/// This struct captures the model and tools configuration, allowing AgentSession
/// to recreate its underlying LanguageModelSession when needed.
public struct DefaultSessionDelegate: LanguageModelSessionDelegate {
    private let factory: @Sendable (Transcript) -> LanguageModelSession

    /// Creates a new delegate with the given factory closure.
    ///
    /// - Parameter factory: A closure that creates a LanguageModelSession from a Transcript.
    public init(factory: @escaping @Sendable (Transcript) -> LanguageModelSession) {
        self.factory = factory
    }

    public func createSession(with transcript: Transcript) -> LanguageModelSession {
        factory(transcript)
    }
}

public final class AgentSession: Sendable {

    // MARK: - Types

    /// The result of sending a message.
    public struct Response: Sendable {
        /// The generated text content.
        public let content: String

        /// All transcript entries added during this request (prompt, toolCalls, toolOutput, response).
        public let entries: [Transcript.Entry]

        /// Time taken to process the request.
        public let duration: Duration

        public init(content: String, entries: [Transcript.Entry], duration: Duration) {
            self.content = content
            self.entries = entries
            self.duration = duration
        }
    }

    // MARK: - Public Properties

    /// Unique identifier for this session.
    public let id: String

    /// The event bus for emitting session events.
    public let eventBus: EventBus

    // MARK: - Private State

    private struct SessionState: Sendable {
        var steeringMessages: [String] = []
        var isProcessing = false
        var waitQueue: [(id: UUID, continuation: CheckedContinuation<Bool, Never>)] = []
    }

    private let state: Mutex<SessionState>
    private let languageModelSessionStorage: Mutex<LanguageModelSession>
    private let delegate: any LanguageModelSessionDelegate

    /// The underlying language model session.
    private var languageModelSession: LanguageModelSession {
        get { languageModelSessionStorage.withLock { $0 } }
        set { languageModelSessionStorage.withLock { $0 = newValue } }
    }

    // MARK: - Initialization

    /// Creates a new session with instructions.
    ///
    /// - Parameters:
    ///   - id: Unique identifier for this session. Defaults to a new UUID.
    ///   - eventBus: The event bus for emitting events. Defaults to a new EventBus.
    ///   - model: The language model to use.
    ///   - tools: Tools available to the model.
    ///   - instructions: Instructions builder for the session.
#if USE_OTHER_MODELS
    public init(
        id: String = UUID().uuidString,
        eventBus: EventBus = EventBus(),
        model: any LanguageModel,
        tools: [any Tool] = [],
        @InstructionsBuilder instructions: () -> Instructions
    ) {
        self.id = id
        self.eventBus = eventBus
        self.state = Mutex(SessionState())
        self.languageModelSessionStorage = Mutex(LanguageModelSession(
            model: model,
            tools: tools,
            instructions: instructions
        ))
        self.delegate = DefaultSessionDelegate { transcript in
            LanguageModelSession(model: model, tools: tools, transcript: transcript)
        }
    }
#else
    public init(
        id: String = UUID().uuidString,
        eventBus: EventBus = EventBus(),
        model: SystemLanguageModel = .default,
        tools: [any Tool] = [],
        @InstructionsBuilder instructions: () -> Instructions
    ) {
        self.id = id
        self.eventBus = eventBus
        self.state = Mutex(SessionState())
        self.languageModelSessionStorage = Mutex(LanguageModelSession(
            model: model,
            tools: tools,
            instructions: instructions
        ))
        self.delegate = DefaultSessionDelegate { transcript in
            LanguageModelSession(model: model, tools: tools, transcript: transcript)
        }
    }
#endif

    /// Creates a new session from an existing transcript.
    ///
    /// Use this initializer to restore a session from a saved state.
    ///
    /// - Parameters:
    ///   - id: Unique identifier for this session.
    ///   - eventBus: The event bus for emitting events. Defaults to a new EventBus.
    ///   - transcript: The transcript to restore from.
    ///   - model: The language model to use.
    ///   - tools: Tools available to the model.
#if USE_OTHER_MODELS
    public init(
        id: String = UUID().uuidString,
        eventBus: EventBus = EventBus(),
        transcript: Transcript,
        model: any LanguageModel,
        tools: [any Tool] = []
    ) {
        self.id = id
        self.eventBus = eventBus
        self.state = Mutex(SessionState())
        self.languageModelSessionStorage = Mutex(LanguageModelSession(
            model: model,
            tools: tools,
            transcript: transcript
        ))
        self.delegate = DefaultSessionDelegate { transcript in
            LanguageModelSession(model: model, tools: tools, transcript: transcript)
        }
    }
#else
    public init(
        id: String = UUID().uuidString,
        eventBus: EventBus = EventBus(),
        transcript: Transcript,
        model: SystemLanguageModel = .default,
        tools: [any Tool] = []
    ) {
        self.id = id
        self.eventBus = eventBus
        self.state = Mutex(SessionState())
        self.languageModelSessionStorage = Mutex(LanguageModelSession(
            model: model,
            tools: tools,
            transcript: transcript
        ))
        self.delegate = DefaultSessionDelegate { transcript in
            LanguageModelSession(model: model, tools: tools, transcript: transcript)
        }
    }
#endif

    /// Creates a new session with an externally provided delegate.
    ///
    /// This initializer allows full control over how LanguageModelSession instances
    /// are created, enabling custom model configurations, tool setups, or testing mocks.
    ///
    /// - Parameters:
    ///   - id: Unique identifier for this session. Defaults to a new UUID.
    ///   - eventBus: The event bus for emitting events. Defaults to a new EventBus.
    ///   - initialSession: The initial LanguageModelSession to use.
    ///   - delegate: The delegate responsible for creating new sessions when needed.
    public init(
        id: String = UUID().uuidString,
        eventBus: EventBus = EventBus(),
        initialSession: LanguageModelSession,
        delegate: any LanguageModelSessionDelegate
    ) {
        self.id = id
        self.eventBus = eventBus
        self.state = Mutex(SessionState())
        self.languageModelSessionStorage = Mutex(initialSession)
        self.delegate = delegate
    }

    // MARK: - Message Handling

    /// Sends a message to the session and waits for the response.
    ///
    /// If the session is currently processing another message, this method waits
    /// for the current processing to complete before starting.
    ///
    /// Any steering messages added via `steer()` will be included in the prompt.
    ///
    /// - Parameter content: The message content.
    /// - Returns: The response containing the generated content and metadata.
    /// - Throws: `CancellationError` if the task was cancelled while waiting.
    public func send(_ content: String) async throws -> Response {
        // Acquire exclusive processing slot (returns false if cancelled while waiting)
        let acquired = await acquireProcessingSlot()
        guard acquired else {
            throw CancellationError()
        }
        defer { releaseProcessingSlot() }

        // Also check cancellation after acquiring in case cancelled during handoff
        try Task.checkCancellation()

        return try await processMessage(content)
    }

    /// Adds a steering message to be included in the **next** prompt.
    ///
    /// Steering messages are accumulated and combined with the next message
    /// sent via `send()`. They are consumed when the prompt is built.
    ///
    /// **Note:** Steering messages added while a prompt is being processed
    /// will be included in the *following* prompt, not the current one.
    ///
    /// - Parameter content: The steering message content.
    public func steer(_ content: String) {
        state.withLock { $0.steeringMessages.append(content) }
    }

    // MARK: - Processing

    /// Acquires the exclusive processing slot, waiting if necessary.
    ///
    /// Uses a continuation queue for efficient FIFO waiting without CPU spinning.
    /// Supports task cancellation - cancelled tasks are removed from the queue.
    ///
    /// - Returns: `true` if slot was acquired, `false` if cancelled while waiting.
    private func acquireProcessingSlot() async -> Bool {
        let waiterID = UUID()

        return await withTaskCancellationHandler {
            await withCheckedContinuation { continuation in
                let shouldResumeImmediately = state.withLock { state -> Bool in
                    if !state.isProcessing {
                        state.isProcessing = true
                        return true
                    }
                    state.waitQueue.append((id: waiterID, continuation: continuation))
                    return false
                }
                if shouldResumeImmediately {
                    continuation.resume(returning: true)
                }
            }
        } onCancel: {
            // Remove from queue and resume with false if still waiting
            let continuation: CheckedContinuation<Bool, Never>? = state.withLock { state in
                if let index = state.waitQueue.firstIndex(where: { $0.id == waiterID }) {
                    let waiter = state.waitQueue.remove(at: index)
                    return waiter.continuation
                }
                return nil
            }
            continuation?.resume(returning: false)
        }
    }

    /// Releases the processing slot and resumes the next waiter if any.
    ///
    /// Resumes continuation outside the lock to prevent potential deadlocks.
    private func releaseProcessingSlot() {
        let nextWaiter: CheckedContinuation<Bool, Never>? = state.withLock { state in
            if let next = state.waitQueue.first {
                state.waitQueue.removeFirst()
                return next.continuation  // isProcessing remains true for next waiter
            }
            state.isProcessing = false
            return nil
        }
        nextWaiter?.resume(returning: true)
    }

    /// Processes a message with any accumulated steering messages.
    ///
    /// Captures the session reference at the start to handle mid-processing
    /// session replacement correctly. If `replaceSession()` is called during
    /// processing, current processing continues with the captured session,
    /// and the next message uses the new session.
    private func processMessage(_ content: String) async throws -> Response {
        let startTime = ContinuousClock.now

        // Capture session reference to handle mid-processing replacement
        let currentSession = languageModelSession

        // Record transcript count before processing to calculate diff later
        let startIndex = currentSession.transcript.count

        // Build prompt with steering messages
        let prompt = buildPrompt(mainMessage: content)

        // Emit prompt submitted event
        await eventBus.emit(SessionEvent(
            name: .promptSubmitted,
            sessionID: id,
            value: prompt
        ))

        // Use captured session for processing
        let response = try await currentSession.respond(to: prompt)

        let duration = ContinuousClock.now - startTime

        // Get all entries added during this request from captured session
        let newEntries = Array(currentSession.transcript.suffix(from: startIndex))

        // Emit response completed event
        await eventBus.emit(SessionEvent(
            name: .responseCompleted,
            sessionID: id,
            value: response.content
        ))

        return Response(content: response.content, entries: newEntries, duration: duration)
    }

    /// Builds a prompt from the main message and any steering messages.
    private func buildPrompt(mainMessage: String) -> String {
        let steering = state.withLock { state -> [String] in
            let messages = state.steeringMessages
            state.steeringMessages.removeAll()
            return messages
        }

        if steering.isEmpty {
            return mainMessage
        }

        // Combine main message with steering messages
        return ([mainMessage] + steering).joined(separator: "\n\n")
    }

    // MARK: - Session State

    /// The current transcript of the session.
    public var transcript: Transcript {
        languageModelSession.transcript
    }

    /// Whether the session is currently generating a response.
    public var isResponding: Bool {
        state.withLock { $0.isProcessing }
    }

    /// The number of pending steering messages.
    public var pendingSteeringCount: Int {
        state.withLock { $0.steeringMessages.count }
    }

    // MARK: - Session Replacement

    /// Replaces the underlying LanguageModelSession with a new one created from the given transcript.
    ///
    /// This can be called at any time, including while processing. If called while processing:
    /// - Current processing continues with the previously captured session
    /// - The next message uses the new session
    ///
    /// This is used for transcript compaction, where the conversation history is compressed
    /// and a new session is created with the compacted transcript. The delegate is responsible
    /// for creating the new session with the appropriate model and tools.
    ///
    /// - Parameter transcript: The transcript to use for the new session.
    public func replaceSession(with transcript: Transcript) {
        languageModelSession = delegate.createSession(with: transcript)
    }

    // MARK: - Persistence

    /// Creates a snapshot of the current session state.
    ///
    /// - Returns: A snapshot that can be saved and restored.
    public func snapshot() -> SessionSnapshot {
        SessionSnapshot(
            id: id,
            transcript: transcript,
            createdAt: Date(),
            updatedAt: Date()
        )
    }

    /// Restores a session from a snapshot.
    ///
    /// - Parameters:
    ///   - snapshot: The snapshot to restore from.
    ///   - eventBus: The event bus for emitting events. Defaults to a new EventBus.
    ///   - model: The language model to use.
    ///   - tools: Tools available to the model.
    /// - Returns: A new session initialized with the snapshot's transcript.
#if USE_OTHER_MODELS
    public static func restore(
        from snapshot: SessionSnapshot,
        eventBus: EventBus = EventBus(),
        model: any LanguageModel,
        tools: [any Tool] = []
    ) -> AgentSession {
        AgentSession(
            id: snapshot.id,
            eventBus: eventBus,
            transcript: snapshot.transcript,
            model: model,
            tools: tools
        )
    }
#else
    public static func restore(
        from snapshot: SessionSnapshot,
        eventBus: EventBus = EventBus(),
        model: SystemLanguageModel = .default,
        tools: [any Tool] = []
    ) -> AgentSession {
        AgentSession(
            id: snapshot.id,
            eventBus: eventBus,
            transcript: snapshot.transcript,
            model: model,
            tools: tools
        )
    }
#endif
}
