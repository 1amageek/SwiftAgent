//
//  ModelStep.swift
//  SwiftAgent
//
//  Created by Norikazu Muramoto on 2025/01/16.
//

import Foundation
import Tracing
import Instrumentation

// MARK: - Type Aliases

/// Type alias for ResponseStream.Snapshot used in Generate streaming
public typealias GenerateSnapshot<T: Generable> = LanguageModelSession.ResponseStream<T>.Snapshot

/// A step that integrates OpenFoundationModels' LanguageModelSession with SwiftAgent
///
/// Generate supports both streaming and non-streaming modes for structured output generation.
///
/// Example usage (non-streaming):
/// ```swift
/// let step = Generate<String, BlogPost>(session: session) { input in
///     Prompt("Write a blog post about: \(input)")
/// }
/// let post = try await step.run("Swift Concurrency")
/// ```
///
/// Example usage (streaming with Snapshot):
/// ```swift
/// let step = Generate<String, BlogPost>(
///     session: session,
///     prompt: { input in
///         Prompt("Write a blog post about: \(input)")
///     },
///     onStream: { snapshot in
///         // snapshot.content is BlogPost.PartiallyGenerated
///         // For custom @Generable types, properties are Optional
///         let partialPost = snapshot.content
///         
///         // Access partial properties safely
///         if let title = partialPost.title {
///             print("Title: \(title)")
///         }
///         
///         if let content = partialPost.content {
///             print("Content length: \(content.count) characters")
///         }
///         
///         // Check if generation is complete (if PartiallyGenerated has isComplete)
///         // print("Is complete: \(partialPost.isComplete)")
///         
///         // Raw content is always available
///         let rawContent = snapshot.rawContent
///         print("Raw content complete: \(rawContent.isComplete)")
///         
///         if let json = rawContent.jsonString {
///             print("Raw JSON: \(json)")
///         }
///     }
/// )
/// let finalPost = try await step.run("Swift Concurrency")
/// ```
///
/// Example usage (with GenerationOptions):
/// ```swift
/// let step = Generate<String, BlogPost>(
///     session: session,
///     options: GenerationOptions(
///         sampling: .random(probabilityThreshold: 0.95),
///         temperature: 0.7,
///         maximumResponseTokens: 2000
///     )
/// ) { input in
///     Prompt("Write a creative blog post about: \(input)")
/// }
/// let post = try await step.run("Future of AI")
/// ```
///
/// When using streaming, the `onStream` handler receives a `ResponseStream.Snapshot`
/// where `snapshot.content` is `Out.PartiallyGenerated` (not `Out` itself).
/// For custom @Generable types, PartiallyGenerated has Optional properties.
/// The final complete result is still returned by the `run` method.
public struct Generate<In: Sendable, Out: Sendable & Generable>: Step {

    public typealias Input = In
    public typealias Output = Out

    private enum SessionSource: @unchecked Sendable {
        case direct(LanguageModelSession)
        case relay(Relay<LanguageModelSession>)
        case context
    }

    private let sessionSource: SessionSource
    private let options: GenerationOptions
    private let maxRetries: Int
    private let promptBuilder: (In) -> Prompt
    private let streamHandler: ((GenerateSnapshot<Out>) async -> Void)?

    private var session: LanguageModelSession {
        switch sessionSource {
        case .direct(let session):
            return session
        case .relay(let relay):
            return relay.wrappedValue
        case .context:
            guard let session = SessionContext.current else {
                fatalError("No LanguageModelSession available in current context. Use withSession { } to provide one.")
            }
            return session
        }
    }

    // MARK: - Direct Session Initializers

    /// Creates a new Generate step with streaming support
    /// - Parameters:
    ///   - session: The LanguageModelSession to use
    ///   - options: Generation options for controlling output
    ///   - maxRetries: Maximum number of retries on generation failure (default: 0)
    ///   - prompt: A closure that builds a Prompt using PromptBuilder
    ///   - onStream: A closure that handles each ResponseStream.Snapshot
    public init(
        session: LanguageModelSession,
        options: GenerationOptions = GenerationOptions(),
        maxRetries: Int = 3,
        @PromptBuilder prompt: @escaping (In) -> Prompt,
        onStream: @escaping (GenerateSnapshot<Out>) async -> Void
    ) {
        self.sessionSource = .direct(session)
        self.options = options
        self.maxRetries = maxRetries
        self.promptBuilder = prompt
        self.streamHandler = onStream
    }

    /// Creates a new Generate step
    /// - Parameters:
    ///   - session: The LanguageModelSession to use
    ///   - options: Generation options for controlling output
    ///   - maxRetries: Maximum number of retries on generation failure (default: 0)
    ///   - prompt: A closure that builds a Prompt using PromptBuilder
    public init(
        session: LanguageModelSession,
        options: GenerationOptions = GenerationOptions(),
        maxRetries: Int = 3,
        @PromptBuilder prompt: @escaping (In) -> Prompt
    ) {
        self.sessionSource = .direct(session)
        self.options = options
        self.maxRetries = maxRetries
        self.promptBuilder = prompt
        self.streamHandler = nil
    }

    /// Creates a new Generate step
    /// - Parameters:
    ///   - session: The LanguageModelSession to use
    ///   - options: Generation options for controlling output
    ///   - maxRetries: Maximum number of retries on generation failure (default: 0)
    ///   - transform: A closure to transform the input to a string prompt
    public init(
        session: LanguageModelSession,
        options: GenerationOptions = GenerationOptions(),
        maxRetries: Int = 3,
        transform: @escaping (In) -> String
    ) {
        self.sessionSource = .direct(session)
        self.options = options
        self.maxRetries = maxRetries
        self.promptBuilder = { input in Prompt(transform(input)) }
        self.streamHandler = nil
    }

    /// Creates a new Generate step
    /// When Input conforms to PromptRepresentable, no prompt builder is needed
    /// - Parameters:
    ///   - session: The LanguageModelSession to use
    ///   - options: Generation options for controlling output
    ///   - maxRetries: Maximum number of retries on generation failure (default: 0)
    public init(
        session: LanguageModelSession,
        options: GenerationOptions = GenerationOptions(),
        maxRetries: Int = 3
    ) where In: PromptRepresentable {
        self.sessionSource = .direct(session)
        self.options = options
        self.maxRetries = maxRetries
        self.promptBuilder = { input in input.promptRepresentation }
        self.streamHandler = nil
    }

    /// Creates a new Generate step with streaming support
    /// When Input conforms to PromptRepresentable
    /// - Parameters:
    ///   - session: The LanguageModelSession to use
    ///   - options: Generation options for controlling output
    ///   - maxRetries: Maximum number of retries on generation failure (default: 0)
    ///   - onStream: A closure that handles each ResponseStream.Snapshot
    public init(
        session: LanguageModelSession,
        options: GenerationOptions = GenerationOptions(),
        maxRetries: Int = 3,
        onStream: @escaping (GenerateSnapshot<Out>) async -> Void
    ) where In: PromptRepresentable {
        self.sessionSource = .direct(session)
        self.options = options
        self.maxRetries = maxRetries
        self.promptBuilder = { input in input.promptRepresentation }
        self.streamHandler = onStream
    }

    // MARK: - Relay Session Initializers

    /// Creates a new Generate step with a shared session via Relay
    /// - Parameters:
    ///   - session: A Relay to a shared LanguageModelSession
    ///   - options: Generation options for controlling output
    ///   - maxRetries: Maximum number of retries on generation failure (default: 0)
    ///   - prompt: A closure that builds a Prompt using PromptBuilder
    public init(
        session: Relay<LanguageModelSession>,
        options: GenerationOptions = GenerationOptions(),
        maxRetries: Int = 3,
        @PromptBuilder prompt: @escaping (In) -> Prompt
    ) {
        self.sessionSource = .relay(session)
        self.options = options
        self.maxRetries = maxRetries
        self.promptBuilder = prompt
        self.streamHandler = nil
    }

    /// Creates a new Generate step with a shared session via Relay and streaming
    /// - Parameters:
    ///   - session: A Relay to a shared LanguageModelSession
    ///   - options: Generation options for controlling output
    ///   - maxRetries: Maximum number of retries on generation failure (default: 0)
    ///   - prompt: A closure that builds a Prompt using PromptBuilder
    ///   - onStream: A closure that handles each ResponseStream.Snapshot
    public init(
        session: Relay<LanguageModelSession>,
        options: GenerationOptions = GenerationOptions(),
        maxRetries: Int = 3,
        @PromptBuilder prompt: @escaping (In) -> Prompt,
        onStream: @escaping (GenerateSnapshot<Out>) async -> Void
    ) {
        self.sessionSource = .relay(session)
        self.options = options
        self.maxRetries = maxRetries
        self.promptBuilder = prompt
        self.streamHandler = onStream
    }

    /// Creates a new Generate step with Relay (backward compatibility)
    /// - Parameters:
    ///   - session: A Relay to a shared LanguageModelSession
    ///   - options: Generation options for controlling output
    ///   - maxRetries: Maximum number of retries on generation failure (default: 0)
    ///   - transform: A closure to transform the input to a string prompt
    public init(
        session: Relay<LanguageModelSession>,
        options: GenerationOptions = GenerationOptions(),
        maxRetries: Int = 3,
        transform: @escaping (In) -> String
    ) {
        self.sessionSource = .relay(session)
        self.options = options
        self.maxRetries = maxRetries
        self.promptBuilder = { input in Prompt(transform(input)) }
        self.streamHandler = nil
    }

    /// Creates a new Generate step with a shared session via Relay
    /// When Input conforms to PromptRepresentable, no prompt builder is needed
    /// - Parameters:
    ///   - session: A Relay to a shared LanguageModelSession
    ///   - options: Generation options for controlling output
    ///   - maxRetries: Maximum number of retries on generation failure (default: 0)
    public init(
        session: Relay<LanguageModelSession>,
        options: GenerationOptions = GenerationOptions(),
        maxRetries: Int = 3
    ) where In: PromptRepresentable {
        self.sessionSource = .relay(session)
        self.options = options
        self.maxRetries = maxRetries
        self.promptBuilder = { input in input.promptRepresentation }
        self.streamHandler = nil
    }

    // MARK: - Context-based Initializers

    /// Creates a new Generate step that uses the session from TaskLocal context
    /// - Parameters:
    ///   - options: Generation options for controlling output
    ///   - maxRetries: Maximum number of retries on generation failure (default: 0)
    ///   - prompt: A closure that builds a Prompt using PromptBuilder
    public init(
        options: GenerationOptions = GenerationOptions(),
        maxRetries: Int = 3,
        @PromptBuilder prompt: @escaping (In) -> Prompt
    ) {
        self.sessionSource = .context
        self.options = options
        self.maxRetries = maxRetries
        self.promptBuilder = prompt
        self.streamHandler = nil
    }

    /// Creates a new Generate step that uses the session from TaskLocal context with streaming
    /// - Parameters:
    ///   - options: Generation options for controlling output
    ///   - maxRetries: Maximum number of retries on generation failure (default: 0)
    ///   - prompt: A closure that builds a Prompt using PromptBuilder
    ///   - onStream: A closure that handles each ResponseStream.Snapshot
    public init(
        options: GenerationOptions = GenerationOptions(),
        maxRetries: Int = 3,
        @PromptBuilder prompt: @escaping (In) -> Prompt,
        onStream: @escaping (GenerateSnapshot<Out>) async -> Void
    ) {
        self.sessionSource = .context
        self.options = options
        self.maxRetries = maxRetries
        self.promptBuilder = prompt
        self.streamHandler = onStream
    }

    /// Creates a new Generate step that uses the session from TaskLocal context
    /// When Input conforms to PromptRepresentable
    /// - Parameters:
    ///   - options: Generation options for controlling output
    ///   - maxRetries: Maximum number of retries on generation failure (default: 0)
    public init(
        options: GenerationOptions = GenerationOptions(),
        maxRetries: Int = 3
    ) where In: PromptRepresentable {
        self.sessionSource = .context
        self.options = options
        self.maxRetries = maxRetries
        self.promptBuilder = { input in input.promptRepresentation }
        self.streamHandler = nil
    }

    @discardableResult
    public func run(_ input: In) async throws -> Out {
        return try await withSpan(
            "Generate.\(Out.self)",
            ofKind: .client
        ) { span in
            // Set basic attributes for LLM call
            span.attributes[SwiftAgentSpanAttributes.stepType] = "LLMGeneration"

            // Build prompt
            let prompt = promptBuilder(input)
            span.addEvent("prompt_generated")

            let maxAttempts = maxRetries + 1
            var lastError: Error?

            for attempt in 1...maxAttempts {
                // Check for cancellation before each attempt
                try Task.checkCancellation()
                try TurnCancellationContext.current?.checkCancellation()

                do {
                    if let handler = streamHandler {
                        // Streaming mode - use streamResponse
                        span.addEvent("streaming_started")
                        var lastContent: Out?

                        let responseStream = session.streamResponse(
                            generating: Out.self,
                            includeSchemaInPrompt: true,
                            options: options
                        ) {
                            prompt
                        }

                        for try await snapshot in responseStream {
                            try Task.checkCancellation()
                            try TurnCancellationContext.current?.checkCancellation()

                            // Pass the snapshot directly to the handler
                            await handler(snapshot)

                            // Try to get the full content from rawContent
                            // This is needed because snapshot.content is PartiallyGenerated
                            if let fullContent = try? Out(snapshot.rawContent) {
                                lastContent = fullContent
                            }
                        }

                        span.addEvent("streaming_completed")

                        guard let result = lastContent else {
                            throw ModelError.generationFailed("No content generated")
                        }
                        return result

                    } else {
                        // Non-streaming mode - use respond
                        // Note: Tool execution happens internally in the LanguageModel implementation
                        // if tools are registered in the session. The model will handle tool calls
                        // automatically based on its implementation (e.g., OpenAI, Anthropic).
                        let response = try await session.respond(
                            generating: Out.self,
                            includeSchemaInPrompt: true,
                            options: options
                        ) {
                            prompt
                        }

                        // Span is successful by default
                        return response.content
                    }
                } catch is CancellationError {
                    // Don't retry on cancellation
                    throw CancellationError()
                } catch {
                    // Check if error is retryable
                    guard shouldRetryGenerationError(error) else {
                        span.recordError(error)
                        throw ModelError.generationFailed(error.localizedDescription)
                    }

                    lastError = error

                    if attempt < maxAttempts {
                        span.addEvent(SpanEvent(name: "retry_attempt_\(attempt)"))
                    }
                }
            }

            // All retry attempts failed
            if let error = lastError {
                span.recordError(error)
                throw ModelError.generationFailed(error.localizedDescription)
            }

            // This should never happen, but satisfy the compiler
            throw ModelError.generationFailed("Unknown error")
        }
    }
}

/// A step that generates string output using OpenFoundationModels
///
/// GenerateText supports both streaming and non-streaming modes for text generation.
///
/// Example usage (non-streaming):
/// ```swift
/// let step = GenerateText<String>(session: session) { input in
///     Prompt("Generate a story about: \(input)")
/// }
/// let story = try await step.run("a brave knight")
/// ```
///
/// Example usage (streaming with Snapshot):
/// ```swift
/// var previousContent = ""
/// let step = GenerateText<String>(
///     session: session,
///     prompt: { input in
///         Prompt("Generate a story about: \(input)")
///     },
///     onStream: { snapshot in
///         // snapshot.content is String.PartiallyGenerated (which is String)
///         // For String, PartiallyGenerated == String
///         let accumulated = snapshot.content
///         
///         // Calculate chunk if needed
///         let chunk = String(accumulated.dropFirst(previousContent.count))
///         previousContent = accumulated
///         
///         print(chunk, terminator: "")  // Display new chunk
///         
///         // Check completion via rawContent
///         if snapshot.rawContent.isComplete {
///             print("\n[Story complete: \(accumulated.count) characters]")
///         }
///     }
/// )
/// let fullStory = try await step.run("a brave knight")
/// ```
///
/// Example usage (streaming - progress tracking):
/// ```swift
/// let step = GenerateText<String>(
///     session: session,
///     prompt: { _ in
///         Prompt("Write a detailed essay")
///     },
///     onStream: { snapshot in
///         let accumulated = snapshot.content
///         print("Progress: \(accumulated.count) characters")
///         
///         // Show progress bar
///         let progress = min(accumulated.count / 1000, 1.0)
///         updateProgressBar(progress)
///         
///         // Check completion
///         if snapshot.rawContent.isComplete {
///             print("Essay generation complete!")
///         }
///     }
/// )
/// let essay = try await step.run("AI")
/// ```
///
/// Example usage (with GenerationOptions for concise output):
/// ```swift
/// let step = GenerateText<String>(
///     session: session,
///     options: GenerationOptions(
///         sampling: .greedy,
///         temperature: 0.3,
///         maximumResponseTokens: 100
///     )
/// ) { topic in
///     Prompt("Write a brief summary about: \(topic)")
/// }
/// let summary = try await step.run("quantum computing")
/// ```
///
/// When using streaming, the `onStream` handler receives a `ResponseStream.Snapshot`
/// containing both the content (accumulated String) and the raw `GeneratedContent`.
/// The complete text is still returned by the `run` method.
public struct GenerateText<In: Sendable>: Step {

    public typealias Input = In
    public typealias Output = String

    private enum SessionSource: @unchecked Sendable {
        case direct(LanguageModelSession)
        case relay(Relay<LanguageModelSession>)
        case context
    }

    private let sessionSource: SessionSource
    private let options: GenerationOptions
    private let promptBuilder: (In) -> Prompt
    private let streamHandler: ((GenerateSnapshot<Output>) async -> Void)?

    private var session: LanguageModelSession {
        switch sessionSource {
        case .direct(let session):
            return session
        case .relay(let relay):
            return relay.wrappedValue
        case .context:
            guard let session = SessionContext.current else {
                fatalError("No LanguageModelSession available in current context. Use withSession { } to provide one.")
            }
            return session
        }
    }

    // MARK: - Direct Session Initializers

    /// Creates a new GenerateText step with streaming support
    /// - Parameters:
    ///   - session: The LanguageModelSession to use
    ///   - options: Generation options for controlling output
    ///   - prompt: A closure that builds a Prompt using PromptBuilder
    ///   - onStream: A closure that handles each ResponseStream.Snapshot
    public init(
        session: LanguageModelSession,
        options: GenerationOptions = GenerationOptions(),
        @PromptBuilder prompt: @escaping (In) -> Prompt,
        onStream: @escaping (GenerateSnapshot<Output>) async -> Void
    ) {
        self.sessionSource = .direct(session)
        self.options = options
        self.promptBuilder = prompt
        self.streamHandler = onStream
    }

    /// Creates a new GenerateText step
    /// - Parameters:
    ///   - session: The LanguageModelSession to use
    ///   - options: Generation options for controlling output
    ///   - prompt: A closure that builds a Prompt using PromptBuilder
    public init(
        session: LanguageModelSession,
        options: GenerationOptions = GenerationOptions(),
        @PromptBuilder prompt: @escaping (In) -> Prompt
    ) {
        self.sessionSource = .direct(session)
        self.options = options
        self.promptBuilder = prompt
        self.streamHandler = nil
    }

    /// Creates a new GenerateText step
    /// - Parameters:
    ///   - session: The LanguageModelSession to use
    ///   - options: Generation options for controlling output
    ///   - transform: A closure to transform the input to a string prompt
    public init(
        session: LanguageModelSession,
        options: GenerationOptions = GenerationOptions(),
        transform: @escaping (In) -> String
    ) {
        self.sessionSource = .direct(session)
        self.options = options
        self.promptBuilder = { input in Prompt(transform(input)) }
        self.streamHandler = nil
    }

    /// Creates a new GenerateText step
    /// When Input conforms to PromptRepresentable, no prompt builder is needed
    /// - Parameters:
    ///   - session: The LanguageModelSession to use
    ///   - options: Generation options for controlling output
    public init(
        session: LanguageModelSession,
        options: GenerationOptions = GenerationOptions()
    ) where In: PromptRepresentable {
        self.sessionSource = .direct(session)
        self.options = options
        self.promptBuilder = { input in input.promptRepresentation }
        self.streamHandler = nil
    }

    /// Creates a new GenerateText step with streaming support
    /// When Input conforms to PromptRepresentable
    /// - Parameters:
    ///   - session: The LanguageModelSession to use
    ///   - options: Generation options for controlling output
    ///   - onStream: A closure that handles each ResponseStream.Snapshot
    public init(
        session: LanguageModelSession,
        options: GenerationOptions = GenerationOptions(),
        onStream: @escaping (GenerateSnapshot<Output>) async -> Void
    ) where In: PromptRepresentable {
        self.sessionSource = .direct(session)
        self.options = options
        self.promptBuilder = { input in input.promptRepresentation }
        self.streamHandler = onStream
    }

    // MARK: - Relay Session Initializers

    /// Creates a new GenerateText step with a shared session via Relay
    /// - Parameters:
    ///   - session: A Relay to a shared LanguageModelSession
    ///   - options: Generation options for controlling output
    ///   - prompt: A closure that builds a Prompt using PromptBuilder
    public init(
        session: Relay<LanguageModelSession>,
        options: GenerationOptions = GenerationOptions(),
        @PromptBuilder prompt: @escaping (In) -> Prompt
    ) {
        self.sessionSource = .relay(session)
        self.options = options
        self.promptBuilder = prompt
        self.streamHandler = nil
    }

    /// Creates a new GenerateText step with a shared session via Relay and streaming
    /// - Parameters:
    ///   - session: A Relay to a shared LanguageModelSession
    ///   - options: Generation options for controlling output
    ///   - prompt: A closure that builds a Prompt using PromptBuilder
    ///   - onStream: A closure that handles each ResponseStream.Snapshot
    public init(
        session: Relay<LanguageModelSession>,
        options: GenerationOptions = GenerationOptions(),
        @PromptBuilder prompt: @escaping (In) -> Prompt,
        onStream: @escaping (GenerateSnapshot<Output>) async -> Void
    ) {
        self.sessionSource = .relay(session)
        self.options = options
        self.promptBuilder = prompt
        self.streamHandler = onStream
    }

    /// Creates a new GenerateText step with Relay (backward compatibility)
    /// - Parameters:
    ///   - session: A Relay to a shared LanguageModelSession
    ///   - options: Generation options for controlling output
    ///   - transform: A closure to transform the input to a string prompt
    public init(
        session: Relay<LanguageModelSession>,
        options: GenerationOptions = GenerationOptions(),
        transform: @escaping (In) -> String
    ) {
        self.sessionSource = .relay(session)
        self.options = options
        self.promptBuilder = { input in Prompt(transform(input)) }
        self.streamHandler = nil
    }

    /// Creates a new GenerateText step with a shared session via Relay
    /// When Input conforms to PromptRepresentable, no prompt builder is needed
    /// - Parameters:
    ///   - session: A Relay to a shared LanguageModelSession
    ///   - options: Generation options for controlling output
    public init(
        session: Relay<LanguageModelSession>,
        options: GenerationOptions = GenerationOptions()
    ) where In: PromptRepresentable {
        self.sessionSource = .relay(session)
        self.options = options
        self.promptBuilder = { input in input.promptRepresentation }
        self.streamHandler = nil
    }

    // MARK: - Context-based Initializers

    /// Creates a new GenerateText step that uses the session from TaskLocal context
    /// - Parameters:
    ///   - options: Generation options for controlling output
    ///   - prompt: A closure that builds a Prompt using PromptBuilder
    public init(
        options: GenerationOptions = GenerationOptions(),
        @PromptBuilder prompt: @escaping (In) -> Prompt
    ) {
        self.sessionSource = .context
        self.options = options
        self.promptBuilder = prompt
        self.streamHandler = nil
    }

    /// Creates a new GenerateText step that uses the session from TaskLocal context with streaming
    /// - Parameters:
    ///   - options: Generation options for controlling output
    ///   - prompt: A closure that builds a Prompt using PromptBuilder
    ///   - onStream: A closure that handles each ResponseStream.Snapshot
    public init(
        options: GenerationOptions = GenerationOptions(),
        @PromptBuilder prompt: @escaping (In) -> Prompt,
        onStream: @escaping (GenerateSnapshot<Output>) async -> Void
    ) {
        self.sessionSource = .context
        self.options = options
        self.promptBuilder = prompt
        self.streamHandler = onStream
    }

    /// Creates a new GenerateText step that uses the session from TaskLocal context
    /// When Input conforms to PromptRepresentable
    /// - Parameters:
    ///   - options: Generation options for controlling output
    public init(
        options: GenerationOptions = GenerationOptions()
    ) where In: PromptRepresentable {
        self.sessionSource = .context
        self.options = options
        self.promptBuilder = { input in input.promptRepresentation }
        self.streamHandler = nil
    }
    
    @discardableResult
    public func run(_ input: In) async throws -> String {
        return try await withSpan(
            "GenerateText",
            ofKind: .client
        ) { span in
            // Set basic attributes for LLM call
            span.attributes[SwiftAgentSpanAttributes.stepType] = "LLMTextGeneration"

            // Build prompt
            let prompt = promptBuilder(input)
            span.addEvent("prompt_generated")

            // Check for cancellation
            try Task.checkCancellation()
            try TurnCancellationContext.current?.checkCancellation()

            do {
                if let handler = streamHandler {
                    // Streaming mode - use streamResponse
                    span.addEvent("streaming_started")
                    var lastContent: String = ""

                    let responseStream = session.streamResponse(
                        options: options
                    ) {
                        prompt
                    }

                    for try await snapshot in responseStream {
                        try Task.checkCancellation()
                        try TurnCancellationContext.current?.checkCancellation()

                        // Pass the snapshot directly to the handler
                        await handler(snapshot)

                        // For String, PartiallyGenerated == String
                        lastContent = snapshot.content
                    }

                    span.addEvent("streaming_completed")
                    return lastContent

                } else {
                    // Non-streaming mode - use respond
                    // Note: Tool execution happens internally in the LanguageModel implementation
                    // if tools are registered in the session. The model will handle tool calls
                    // automatically based on its implementation (e.g., OpenAI, Anthropic).
                    let response = try await session.respond(
                        options: options
                    ) {
                        prompt
                    }

                    // Span is successful by default
                    return response.content
                }
            } catch is CancellationError {
                throw CancellationError()
            } catch {
                span.recordError(error)
                throw ModelError.generationFailed(error.localizedDescription)
            }
        }
    }
}

/// Errors that can occur during model operations
public enum ModelError: Error, LocalizedError {
    case generationFailed(String)
    case invalidInput(String)
    case toolExecutionFailed(String)
    case modelUnavailable(String)
    case configurationError(String)
    case networkError(String)

    public var errorDescription: String? {
        switch self {
        case .generationFailed(let message):
            return "Generation failed: \(message)"
        case .invalidInput(let message):
            return "Invalid input: \(message)"
        case .toolExecutionFailed(let message):
            return "Tool execution failed: \(message)"
        case .modelUnavailable(let message):
            return "Model unavailable: \(message)"
        case .configurationError(let message):
            return "Configuration error: \(message)"
        case .networkError(let message):
            return "Network error: \(message)"
        }
    }

    /// Recoverable errors that can be retried
    public var isRecoverable: Bool {
        switch self {
        case .networkError, .modelUnavailable:
            return true
        case .generationFailed, .invalidInput, .toolExecutionFailed, .configurationError:
            return false
        }
    }
}

// MARK: - Retry Logic

/// Determines if an error should trigger a retry.
/// Only errors that may succeed on retry should return true.
/// - Parameter error: The error to evaluate
/// - Returns: `true` if the error is recoverable and retry may succeed
func shouldRetryGenerationError(_ error: Error) -> Bool {
    // Check for GenerationError from LanguageModelSession
    if let generationError = error as? LanguageModelSession.GenerationError {
        switch generationError {
        // Retryable: Generation/parsing may succeed on retry
        case .decodingFailure:
            return true

        // Not retryable: These errors won't be resolved by retrying with the same input
        case .exceededContextWindowSize,
             .assetsUnavailable,
             .guardrailViolation,
             .unsupportedGuide,
             .unsupportedLanguageOrLocale,
             .rateLimited,        // Would need delay, not immediate retry
             .concurrentRequests, // Would need delay, not immediate retry
             .refusal:
            return false

        @unknown default:
            return false
        }
    }

    // Check for DecodingError (JSON parsing errors)
    if error is DecodingError {
        return true
    }

    // Unknown errors: don't retry
    return false
}
