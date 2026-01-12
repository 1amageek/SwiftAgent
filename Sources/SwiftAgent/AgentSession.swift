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
/// and receiving responses. It supports queuing messages when the session is processing,
/// with automatic queue draining for real-time steering of the agent.
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
/// ## Event Integration
///
/// AgentSession automatically emits events through its EventBus:
///
/// ```swift
/// let eventBus = EventBus()
/// eventBus.on(.promptSubmitted) { event in
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
/// ## Real-time Steering and Auto-Draining
///
/// Messages can be sent at any time. If the session is currently processing,
/// the message is queued and will be **automatically processed** when the current
/// operation completes. The queue is drained in a loop until empty.
///
/// **Important**: `send()` returns only the response for the *initial* message.
/// - `.completed`: The message was processed immediately.
/// - `.queued`: The message was queued. Its response will be emitted via
///   `.responseCompleted` event when processed.
///
/// ```swift
/// Task {
///     let response = try await session.send("Write a function...")
///     // This returns the response for "Write a function..."
/// }
///
/// // This message will be queued and auto-processed
/// Task {
///     let result = try await session.send("Make sure to use async/await")
///     // result is .queued - response comes via event
/// }
///
/// // Listen for queued message responses
/// eventBus.on(.responseCompleted) { event in
///     // Handle response for queued messages
/// }
/// ```
///
/// ## Queue Behavior
///
/// - **FIFO Order**: Messages are processed in the order they were received.
/// - **Batching**: Queued messages are batched together in each processing cycle.
/// - **Back-pressure**: Queue has a maximum size (default: 100). Exceeding it throws
///   `SessionError.queueFull`.
/// - **Error Handling**: Errors during queue processing are emitted via `.notification`
///   event and don't stop the drain loop.
///
/// ## Configuration
///
/// ```swift
/// let config = SessionConfiguration(maxQueueSize: 50)
/// let session = AgentSession(configuration: config, tools: myTools) {
///     Instructions("...")
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
/// Configuration for AgentSession behavior.
public struct SessionConfiguration: Sendable {
    /// Maximum number of messages that can be queued while processing.
    /// When exceeded, `send()` throws `SessionError.queueFull`.
    public let maxQueueSize: Int

    /// Default configuration with reasonable limits.
    public static let `default` = SessionConfiguration(maxQueueSize: 100)

    /// Creates a new session configuration.
    /// - Parameter maxQueueSize: Maximum queue size. Defaults to 100.
    public init(maxQueueSize: Int = 100) {
        self.maxQueueSize = maxQueueSize
    }
}

/// Errors that can occur during session operations.
public enum SessionError: Error, Sendable {
    /// The message queue is full. Try again later or increase maxQueueSize.
    case queueFull(currentSize: Int, maxSize: Int)
}

public final class AgentSession: Sendable {

    // MARK: - Types

    /// A message sent to the session.
    public struct Message: Sendable, Identifiable, Codable {
        /// Unique identifier for the message.
        public let id: String

        /// The content of the message.
        public let content: String

        /// When the message was created.
        public let timestamp: Date

        /// Creates a new message.
        public init(id: String = UUID().uuidString, content: String) {
            self.id = id
            self.content = content
            self.timestamp = Date()
        }
    }

    /// The result of sending a message.
    public enum Response: Sendable {
        /// The message was processed and a response was generated.
        /// - Parameters:
        ///   - content: The generated text content.
        ///   - entries: All transcript entries added during this request (prompt, toolCalls, toolOutput, response).
        ///   - duration: Time taken to process the request.
        case completed(String, entries: [Transcript.Entry], duration: Duration)

        /// The message was queued because the session is currently processing.
        case queued(Message)

        /// The generated content (for completed responses).
        public var content: String? {
            switch self {
            case .completed(let content, _, _):
                return content
            case .queued:
                return nil
            }
        }

        /// Whether the response is completed.
        public var isCompleted: Bool {
            if case .completed = self { return true }
            return false
        }
    }

    // MARK: - Public Properties

    /// Unique identifier for this session.
    public let id: String

    /// The event bus for emitting session events.
    public let eventBus: EventBus

    /// The configuration for this session.
    public let configuration: SessionConfiguration

    // MARK: - Private State

    private struct SessionState: Sendable {
        var messageQueue: [Message] = []
        var isProcessing = false
    }

    private let state: Mutex<SessionState>
    private let languageModelSession: LanguageModelSession
    private let tools: [any Tool]

    // MARK: - Initialization

    /// Creates a new session with instructions.
    ///
    /// - Parameters:
    ///   - id: Unique identifier for this session. Defaults to a new UUID.
    ///   - eventBus: The event bus for emitting events. Defaults to a new EventBus.
    ///   - configuration: Session configuration. Defaults to `.default`.
    ///   - model: The language model to use.
    ///   - tools: Tools available to the model.
    ///   - instructions: Instructions builder for the session.
#if USE_OTHER_MODELS
    public init(
        id: String = UUID().uuidString,
        eventBus: EventBus = EventBus(),
        configuration: SessionConfiguration = .default,
        model: any LanguageModel,
        tools: [any Tool] = [],
        @InstructionsBuilder instructions: () -> Instructions
    ) {
        self.id = id
        self.eventBus = eventBus
        self.configuration = configuration
        self.tools = tools
        self.state = Mutex(SessionState())
        self.languageModelSession = LanguageModelSession(
            model: model,
            tools: tools,
            instructions: instructions
        )
    }
#else
    public init(
        id: String = UUID().uuidString,
        eventBus: EventBus = EventBus(),
        configuration: SessionConfiguration = .default,
        model: SystemLanguageModel = .default,
        tools: [any Tool] = [],
        @InstructionsBuilder instructions: () -> Instructions
    ) {
        self.id = id
        self.eventBus = eventBus
        self.configuration = configuration
        self.tools = tools
        self.state = Mutex(SessionState())
        self.languageModelSession = LanguageModelSession(
            model: model,
            tools: tools,
            instructions: instructions
        )
    }
#endif

    /// Creates a new session from an existing transcript.
    ///
    /// Use this initializer to restore a session from a saved state.
    ///
    /// - Parameters:
    ///   - id: Unique identifier for this session.
    ///   - eventBus: The event bus for emitting events. Defaults to a new EventBus.
    ///   - configuration: Session configuration. Defaults to `.default`.
    ///   - transcript: The transcript to restore from.
    ///   - model: The language model to use.
    ///   - tools: Tools available to the model.
#if USE_OTHER_MODELS
    public init(
        id: String = UUID().uuidString,
        eventBus: EventBus = EventBus(),
        configuration: SessionConfiguration = .default,
        transcript: Transcript,
        model: any LanguageModel,
        tools: [any Tool] = []
    ) {
        self.id = id
        self.eventBus = eventBus
        self.configuration = configuration
        self.tools = tools
        self.state = Mutex(SessionState())
        self.languageModelSession = LanguageModelSession(
            model: model,
            tools: tools,
            transcript: transcript
        )
    }
#else
    public init(
        id: String = UUID().uuidString,
        eventBus: EventBus = EventBus(),
        configuration: SessionConfiguration = .default,
        transcript: Transcript,
        model: SystemLanguageModel = .default,
        tools: [any Tool] = []
    ) {
        self.id = id
        self.eventBus = eventBus
        self.configuration = configuration
        self.tools = tools
        self.state = Mutex(SessionState())
        self.languageModelSession = LanguageModelSession(
            model: model,
            tools: tools,
            transcript: transcript
        )
    }
#endif

    // MARK: - Message Handling

    /// Sends a message to the session.
    ///
    /// If the session is currently processing another message, this message
    /// will be queued and automatically processed when the current operation completes.
    ///
    /// **Important**: The returned `Response` is only for the *initial* message.
    /// - `.completed`: The message was processed immediately and this is the response.
    /// - `.queued`: The message was queued during processing. It will be automatically
    ///   processed, and the response will be emitted via `.responseCompleted` event.
    ///
    /// Messages are processed in FIFO order. Queued messages are batched together
    /// with subsequent messages in the same processing cycle.
    ///
    /// - Parameter content: The message content.
    /// - Returns: The response (completed or queued).
    /// - Throws: `SessionError.queueFull` if the queue exceeds `configuration.maxQueueSize`.
    public func send(_ content: String) async throws -> Response {
        let message = Message(content: content)

        let result = state.withLock { state -> Result<Bool, SessionError> in
            if state.isProcessing {
                if state.messageQueue.count >= configuration.maxQueueSize {
                    return .failure(.queueFull(
                        currentSize: state.messageQueue.count,
                        maxSize: configuration.maxQueueSize
                    ))
                }
                state.messageQueue.append(message)
                return .success(true)  // queued
            }
            return .success(false)  // process immediately
        }

        switch result {
        case .failure(let error):
            throw error
        case .success(true):
            return .queued(message)
        case .success(false):
            return try await process(message)
        }
    }

    /// Processes a message and any queued messages.
    ///
    /// This method processes the initial message, then drains any messages
    /// that were queued during processing. Only the first response is returned;
    /// subsequent responses are emitted via events.
    private func process(_ message: Message) async throws -> Response {
        state.withLock { $0.isProcessing = true }

        // Process initial message and get the first response
        let firstResponse: Response
        do {
            firstResponse = try await processMessages(initialMessage: message)
        } catch {
            // On error, drain queue and reset state before re-throwing
            await drainRemainingQueue()
            state.withLock { $0.isProcessing = false }
            throw error
        }

        // Drain any messages that were queued during processing
        await drainRemainingQueue()

        state.withLock { $0.isProcessing = false }

        return firstResponse
    }

    /// Processes the initial message along with any currently queued messages.
    private func processMessages(initialMessage: Message) async throws -> Response {
        // Emit prompt submitted event
        await eventBus.emit(SessionEvent(
            name: .promptSubmitted,
            sessionID: id,
            value: initialMessage.content
        ))

        let startTime = ContinuousClock.now

        // Record transcript count before processing to calculate diff later
        let startIndex = languageModelSession.transcript.count

        // Include any queued messages (FIFO: queued first, then initial)
        let queuedMessages = state.withLock { state -> [Message] in
            let messages = state.messageQueue
            state.messageQueue.removeAll()
            return messages
        }
        let allMessages = queuedMessages + [initialMessage]
        let prompt = buildPrompt(from: allMessages)

        let response = try await languageModelSession.respond(to: prompt)

        let duration = ContinuousClock.now - startTime

        // Get all entries added during this request (prompt, toolCalls, toolOutput, response)
        let newEntries = Array(languageModelSession.transcript.suffix(from: startIndex))

        // Emit response completed event
        await eventBus.emit(SessionEvent(
            name: .responseCompleted,
            sessionID: id,
            value: response.content
        ))

        return .completed(response.content, entries: newEntries, duration: duration)
    }

    /// Drains and processes any messages that were queued during processing.
    ///
    /// Since callers already received `.queued` response, results are emitted
    /// via `.responseCompleted` events. Errors don't stop the drain loop;
    /// they're emitted via `.notification` events.
    ///
    /// Messages are processed in FIFO order, batched together in each cycle.
    private func drainRemainingQueue() async {
        while true {
            // Atomically get all pending messages
            let pendingMessages = state.withLock { state -> [Message] in
                let messages = state.messageQueue
                state.messageQueue.removeAll()
                return messages
            }

            if pendingMessages.isEmpty {
                return
            }

            // Process the queued messages
            do {
                let prompt = buildPrompt(from: pendingMessages)

                // Emit event for the batched prompt
                await eventBus.emit(SessionEvent(
                    name: .promptSubmitted,
                    sessionID: id,
                    value: prompt
                ))

                let response = try await languageModelSession.respond(to: prompt)

                // Emit response completed event
                await eventBus.emit(SessionEvent(
                    name: .responseCompleted,
                    sessionID: id,
                    value: response.content
                ))
            } catch {
                // Log error but continue draining - callers already have .queued response
                await eventBus.emit(SessionEvent(
                    name: .notification,
                    sessionID: id,
                    value: "Error processing queued messages: \(error.localizedDescription)"
                ))
            }
        }
    }

    /// Builds a prompt from multiple messages.
    private func buildPrompt(from messages: [Message]) -> String {
        if messages.count == 1 {
            return messages[0].content
        }
        return messages.map { $0.content }.joined(separator: "\n\n")
    }

    // MARK: - Session State

    /// The current transcript of the session.
    public var transcript: Transcript {
        languageModelSession.transcript
    }

    /// The number of messages waiting to be processed.
    public var pendingMessageCount: Int {
        state.withLock { $0.messageQueue.count }
    }

    /// Whether the session is currently generating a response.
    public var isResponding: Bool {
        state.withLock { $0.isProcessing }
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
    ///   - configuration: Session configuration. Defaults to `.default`.
    ///   - model: The language model to use.
    ///   - tools: Tools available to the model.
    /// - Returns: A new session initialized with the snapshot's transcript.
#if USE_OTHER_MODELS
    public static func restore(
        from snapshot: SessionSnapshot,
        eventBus: EventBus = EventBus(),
        configuration: SessionConfiguration = .default,
        model: any LanguageModel,
        tools: [any Tool] = []
    ) -> AgentSession {
        AgentSession(
            id: snapshot.id,
            eventBus: eventBus,
            configuration: configuration,
            transcript: snapshot.transcript,
            model: model,
            tools: tools
        )
    }
#else
    public static func restore(
        from snapshot: SessionSnapshot,
        eventBus: EventBus = EventBus(),
        configuration: SessionConfiguration = .default,
        model: SystemLanguageModel = .default,
        tools: [any Tool] = []
    ) -> AgentSession {
        AgentSession(
            id: snapshot.id,
            eventBus: eventBus,
            configuration: configuration,
            transcript: snapshot.transcript,
            model: model,
            tools: tools
        )
    }
#endif
}
