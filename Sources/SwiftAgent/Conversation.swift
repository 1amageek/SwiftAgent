//
//  Conversation.swift
//  SwiftAgent
//
//  Created by SwiftAgent on 2025/01/08.
//

import Foundation
import Synchronization

/// A thread-safe class that manages an interactive session with a language model.
///
/// `Conversation` provides a simple interface for sending messages to a language model
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
/// let conversation = Conversation(languageModelSession: languageModelSession) {
///     GenerateText()
/// }
///
/// let response = try await conversation.send("Hello!")
/// print(response.content)
/// ```
///
/// ## Multimodal Input
///
/// ```swift
/// let response = try await conversation.send(Prompt {
///     "What is in this image?"
///     PromptImage(source: .url(imageURL))
/// })
/// ```
///
/// ## Steering
///
/// Use `steer()` to add additional context to the **next** prompt:
///
/// ```swift
/// conversation.steer("Make sure to use async/await")
/// conversation.steer("Add error handling")
///
/// let response = try await conversation.send("Write a function...")
/// print(response.content)
/// ```
///
/// **Note:** Steering messages added while a prompt is being processed
/// will be included in the *following* prompt, not the current one.

public final class Conversation: Sendable {

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

    // MARK: - Private State

    private struct SessionState: Sendable {
        var steeringMessages: [Prompt] = []
        var isProcessing = false
        var waitQueue: [(id: UUID, continuation: CheckedContinuation<Bool, Never>)] = []
        var inputContinuation: AsyncStream<Prompt>.Continuation?
    }

    private let state: Mutex<SessionState>
    private let languageModelSession: LanguageModelSession
    private let step: AnyStep<Prompt, String>
    private let inputStreamStorage: Mutex<AsyncStream<Prompt>>

    // MARK: - Initialization

    /// Creates a new session with a pre-configured LanguageModelSession and a Step.
    ///
    /// - Parameters:
    ///   - id: Unique identifier for this session. Defaults to a new UUID.
    ///   - languageModelSession: The LanguageModelSession to use.
    ///   - step: A `@StepBuilder` closure that defines the processing pipeline.
    public init<S: Step & Sendable>(
        id: String = UUID().uuidString,
        languageModelSession: LanguageModelSession,
        @StepBuilder step: () -> S
    ) where S.Input == Prompt, S.Output == String {
        self.id = id
        self.step = AnyStep(step())
        var inputContinuation: AsyncStream<Prompt>.Continuation?
        let inputStream = AsyncStream<Prompt> { continuation in
            inputContinuation = continuation
        }
        self.inputStreamStorage = Mutex(inputStream)
        self.state = Mutex(SessionState(inputContinuation: inputContinuation))
        self.languageModelSession = languageModelSession
    }

    // MARK: - Message Handling

    /// Sends a multimodal prompt to the session and waits for the response.
    ///
    /// If the session is currently processing another message, this method waits
    /// for the current processing to complete before starting.
    ///
    /// Any steering messages added via `steer()` will be included in the prompt.
    ///
    /// - Parameter content: The prompt content (text, images, or both).
    /// - Returns: The response containing the generated content and metadata.
    /// - Throws: `CancellationError` if the task was cancelled while waiting.
    public func send(_ content: Prompt) async throws -> Response {
        let acquired = await acquireProcessingSlot()
        guard acquired else {
            throw CancellationError()
        }
        defer { releaseProcessingSlot() }

        try Task.checkCancellation()

        return try await processMessage(content)
    }

    /// Sends a text message to the session and waits for the response.
    ///
    /// Convenience overload that wraps the string in a `Prompt`.
    ///
    /// - Parameter content: The text message content.
    /// - Returns: The response containing the generated content and metadata.
    /// - Throws: `CancellationError` if the task was cancelled while waiting.
    public func send(_ content: String) async throws -> Response {
        try await send(Prompt(content))
    }

    /// Adds a steering prompt to be included in the **next** message.
    ///
    /// Steering messages are accumulated and combined with the next message
    /// sent via `send()`. They are consumed when the prompt is built.
    ///
    /// - Parameter content: The steering prompt content.
    public func steer(_ content: Prompt) {
        state.withLock { $0.steeringMessages.append(content) }
    }

    /// Adds a text steering message to be included in the **next** message.
    ///
    /// Convenience overload that wraps the string in a `Prompt`.
    ///
    /// - Parameter content: The steering message content.
    public func steer(_ content: String) {
        steer(Prompt(content))
    }

    // MARK: - Input Queue

    /// Adds a prompt to the input queue.
    ///
    /// Messages added via this method are processed in FIFO order by the agent loop.
    ///
    /// - Parameter message: The prompt to add to the input queue.
    public func input(_ message: Prompt) {
        _ = state.withLock { state in
            state.inputContinuation?.yield(message)
        }
    }

    /// Adds a text message to the input queue.
    ///
    /// Convenience overload that wraps the string in a `Prompt`.
    ///
    /// - Parameter message: The text message to add to the input queue.
    public func input(_ message: String) {
        input(Prompt(message))
    }

    /// Waits for the next input from the queue.
    ///
    /// This method suspends until input is available in the queue.
    /// It is typically called in a loop by the agent to process incoming messages.
    ///
    /// - Returns: The next input prompt from the queue.
    /// - Throws: `CancellationError` if the task is cancelled or the stream ends.
    public func waitForInput() async throws -> Prompt {
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
    private func releaseProcessingSlot() {
        let nextWaiter: CheckedContinuation<Bool, Never>? = state.withLock { state in
            if let next = state.waitQueue.first {
                state.waitQueue.removeFirst()
                return next.continuation
            }
            state.isProcessing = false
            return nil
        }
        nextWaiter?.resume(returning: true)
    }

    /// Processes a message with any accumulated steering messages.
    private func processMessage(_ content: Prompt) async throws -> Response {
        let startTime = ContinuousClock.now

        let currentSession = languageModelSession

        let startIndex = currentSession.transcript.count

        let prompt = buildPrompt(mainMessage: content)

        let finalContent = try await withSession(currentSession) {
            try await step.run(prompt)
        }

        let duration = ContinuousClock.now - startTime

        let newEntries = Array(currentSession.transcript.suffix(from: startIndex))

        return Response(content: finalContent, entries: newEntries, duration: duration)
    }

    /// Builds a prompt from the main message and any steering messages.
    private func buildPrompt(mainMessage: Prompt) -> Prompt {
        let steering = state.withLock { state -> [Prompt] in
            let messages = state.steeringMessages
            state.steeringMessages.removeAll()
            return messages
        }

        if steering.isEmpty {
            return mainMessage
        }

        return Prompt {
            mainMessage
            for s in steering { s }
        }
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
