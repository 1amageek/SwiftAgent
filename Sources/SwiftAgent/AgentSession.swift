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
/// let languageModelSession = LanguageModelSession(model: model, tools: myTools) {
///     Instructions("You are a helpful assistant.")
/// }
/// let agentSession = AgentSession(languageModelSession: languageModelSession)
///
/// let response = try await agentSession.send("Hello!")
/// print(response.content)
/// ```
///
/// ## Steering
///
/// Use `steer()` to add additional context to the **next** prompt:
///
/// ```swift
/// // Add steering hints before sending
/// agentSession.steer("Make sure to use async/await")
/// agentSession.steer("Add error handling")
///
/// // Steering messages are combined with the next send()
/// let response = try await agentSession.send("Write a function...")
/// print(response.content)
/// ```
///
/// **Note:** Steering messages added while a prompt is being processed
/// will be included in the *following* prompt, not the current one.

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
        var inputContinuation: AsyncStream<String>.Continuation?
    }

    private let state: Mutex<SessionState>
    private let languageModelSession: LanguageModelSession
    private let inputStreamStorage: Mutex<AsyncStream<String>>

    // MARK: - Initialization

    /// Creates a new session with a pre-configured LanguageModelSession.
    ///
    /// - Parameters:
    ///   - id: Unique identifier for this session. Defaults to a new UUID.
    ///   - eventBus: The event bus for emitting events. Defaults to a new EventBus.
    ///   - languageModelSession: The LanguageModelSession to use.
    public init(
        id: String = UUID().uuidString,
        eventBus: EventBus = EventBus(),
        languageModelSession: LanguageModelSession
    ) {
        self.id = id
        self.eventBus = eventBus
        var inputContinuation: AsyncStream<String>.Continuation?
        let inputStream = AsyncStream<String> { continuation in
            inputContinuation = continuation
        }
        self.inputStreamStorage = Mutex(inputStream)
        self.state = Mutex(SessionState(inputContinuation: inputContinuation))
        self.languageModelSession = languageModelSession
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

    /// Sends a message to the session with optional token-delta callbacks.
    ///
    /// This overload allows callers to receive incremental token output
    /// during generation. The callback receives `(delta, accumulated)` pairs.
    ///
    /// - Parameters:
    ///   - content: The message content.
    ///   - onTokenDelta: Optional callback invoked for each token delta.
    /// - Returns: The response containing the generated content and metadata.
    /// - Throws: `CancellationError` if the task was cancelled while waiting.
    public func send(
        _ content: String,
        onTokenDelta: (@Sendable (String, String) async -> Void)? = nil
    ) async throws -> Response {
        let acquired = await acquireProcessingSlot()
        guard acquired else {
            throw CancellationError()
        }
        defer { releaseProcessingSlot() }

        try Task.checkCancellation()

        return try await processMessage(content, onTokenDelta: onTokenDelta)
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

    // MARK: - Input Queue

    /// Adds a message to the input queue.
    ///
    /// Messages added via this method are processed in FIFO order by the agent loop.
    /// If the agent is currently processing another message, this message will be
    /// queued and processed after the current message completes.
    ///
    /// - Parameter message: The message to add to the input queue.
    public func input(_ message: String) {
        _ = state.withLock { state in
            state.inputContinuation?.yield(message)
        }
    }

    /// Waits for the next input from the queue.
    ///
    /// This method suspends until input is available in the queue.
    /// It is typically called in a loop by the agent to process incoming messages.
    ///
    /// - Returns: The next input message from the queue.
    /// - Throws: `CancellationError` if the task is cancelled or the stream ends.
    public func waitForInput() async throws -> String {
        let stream = inputStreamStorage.withLock { $0 }
        for await input in stream {
            return input
        }
        throw CancellationError()
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
    private func processMessage(
        _ content: String,
        onTokenDelta: (@Sendable (String, String) async -> Void)? = nil
    ) async throws -> Response {
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
        let finalContent: String

        if let onTokenDelta {
            // Streaming mode — invoke callback for each incremental delta
            var accumulated = ""
            let responseStream = currentSession.streamResponse {
                Prompt(prompt)
            }
            for try await snapshot in responseStream {
                let snapshotContent = snapshot.content
                if snapshotContent.count > accumulated.count {
                    let delta = String(snapshotContent.dropFirst(accumulated.count))
                    await onTokenDelta(delta, snapshotContent)
                }
                accumulated = snapshotContent
            }
            finalContent = accumulated
        } else {
            // Non-streaming mode — single respond call
            let response = try await currentSession.respond(to: prompt)
            finalContent = response.content
        }

        let duration = ContinuousClock.now - startTime

        // Get all entries added during this request from captured session
        let newEntries = Array(currentSession.transcript.suffix(from: startIndex))

        // Emit response completed event
        await eventBus.emit(SessionEvent(
            name: .responseCompleted,
            sessionID: id,
            value: finalContent
        ))

        return Response(content: finalContent, entries: newEntries, duration: duration)
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
}
