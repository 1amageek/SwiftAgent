//
//  AgentSession.swift
//  SwiftAgent
//
//  Created by SwiftAgent on 2025/01/08.
//

import Foundation

/// An actor that manages an interactive session with a language model.
///
/// `AgentSession` provides a simple interface for sending messages to a language model
/// and receiving responses. It supports queuing messages when the session is processing,
/// allowing real-time steering of the agent.
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
/// ## Real-time Steering
///
/// Messages can be sent at any time. If the session is currently processing,
/// the message is queued and will be included in the next response cycle.
///
/// ```swift
/// Task {
///     let response = try await session.send("Write a function...")
/// }
///
/// // This message will be queued and included in the processing
/// Task {
///     _ = try await session.send("Make sure to use async/await")
/// }
/// ```
///
/// ## Persistence
///
/// Sessions can be saved and restored using `SessionSnapshot`:
///
/// ```swift
/// // Save
/// let snapshot = await session.snapshot()
/// try await store.save(snapshot)
///
/// // Restore
/// if let snapshot = try await store.load(id: sessionID) {
///     let restored = AgentSession.restore(from: snapshot, tools: myTools)
/// }
/// ```
public actor AgentSession {

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
        case completed(String, transcript: [Transcript.Entry], duration: Duration)

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

    // MARK: - State

    private var languageModelSession: LanguageModelSession
    private var messageQueue: [Message] = []
    private var isProcessing = false
    private let tools: [any Tool]

    // MARK: - Initialization

    /// Creates a new session with instructions.
    ///
    /// - Parameters:
    ///   - model: The language model to use.
    ///   - tools: Tools available to the model.
    ///   - instructions: Instructions builder for the session.
#if USE_OTHER_MODELS
    public init(
        model: any LanguageModel,
        tools: [any Tool] = [],
        @InstructionsBuilder instructions: () -> Instructions
    ) {
        self.tools = tools
        self.languageModelSession = LanguageModelSession(
            model: model,
            tools: tools,
            instructions: instructions
        )
    }
#else
    public init(
        model: SystemLanguageModel = .default,
        tools: [any Tool] = [],
        @InstructionsBuilder instructions: () -> Instructions
    ) {
        self.tools = tools
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
    ///   - transcript: The transcript to restore from.
    ///   - model: The language model to use.
    ///   - tools: Tools available to the model.
#if USE_OTHER_MODELS
    public init(
        transcript: Transcript,
        model: any LanguageModel,
        tools: [any Tool] = []
    ) {
        self.tools = tools
        self.languageModelSession = LanguageModelSession(
            model: model,
            tools: tools,
            transcript: transcript
        )
    }
#else
    public init(
        transcript: Transcript,
        model: SystemLanguageModel = .default,
        tools: [any Tool] = []
    ) {
        self.tools = tools
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
    /// will be queued and included in the next processing cycle.
    ///
    /// - Parameter content: The message content.
    /// - Returns: The response (completed or queued).
    /// - Throws: An error if message processing fails.
    public func send(_ content: String) async throws -> Response {
        let message = Message(content: content)

        if isProcessing {
            messageQueue.append(message)
            return .queued(message)
        }

        return try await process(message)
    }

    /// Processes a message and any queued messages.
    private func process(_ message: Message) async throws -> Response {
        isProcessing = true
        defer { isProcessing = false }

        let startTime = ContinuousClock.now

        // Include any queued messages
        let allMessages = consumeQueue() + [message]
        let prompt = buildPrompt(from: allMessages)

        let response = try await languageModelSession.respond(to: prompt)

        let duration = ContinuousClock.now - startTime
        let recentEntries = Array(languageModelSession.transcript.suffix(2))

        return .completed(response.content, transcript: recentEntries, duration: duration)
    }

    /// Consumes and returns all queued messages.
    private func consumeQueue() -> [Message] {
        let messages = messageQueue
        messageQueue.removeAll()
        return messages
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
        messageQueue.count
    }

    /// Whether the session is currently generating a response.
    public var isResponding: Bool {
        isProcessing
    }

    // MARK: - Persistence

    /// Creates a snapshot of the current session state.
    ///
    /// - Parameter id: The snapshot ID (defaults to a new UUID).
    /// - Returns: A snapshot that can be saved and restored.
    public func snapshot(id: String = UUID().uuidString) -> SessionSnapshot {
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
    ///   - model: The language model to use.
    ///   - tools: Tools available to the model.
    /// - Returns: A new session initialized with the snapshot's transcript.
#if USE_OTHER_MODELS
    public static func restore(
        from snapshot: SessionSnapshot,
        model: any LanguageModel,
        tools: [any Tool] = []
    ) -> AgentSession {
        AgentSession(
            transcript: snapshot.transcript,
            model: model,
            tools: tools
        )
    }
#else
    public static func restore(
        from snapshot: SessionSnapshot,
        model: SystemLanguageModel = .default,
        tools: [any Tool] = []
    ) -> AgentSession {
        AgentSession(
            transcript: snapshot.transcript,
            model: model,
            tools: tools
        )
    }
#endif
}
