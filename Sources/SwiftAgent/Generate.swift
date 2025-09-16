//
//  ModelStep.swift
//  SwiftAgent
//
//  Created by Norikazu Muramoto on 2025/01/16.
//

import Foundation
import OpenFoundationModels
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
/// let step = Generate<String, BlogPost>(session: relay) { input in
///     Prompt("Write a blog post about: \(input)")
/// }
/// let post = try await step.run("Swift Concurrency")
/// ```
///
/// Example usage (streaming with Snapshot):
/// ```swift
/// let step = Generate<String, BlogPost>(
///     session: relay,
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
///     session: relay,
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
    
    private let session: Relay<LanguageModelSession>
    private let options: GenerationOptions
    private let promptBuilder: (In) -> Prompt
    private let streamHandler: ((GenerateSnapshot<Out>) async -> Void)?
    
    /// Creates a new Generate step with streaming support
    /// - Parameters:
    ///   - session: A Relay to a shared LanguageModelSession
    ///   - options: Generation options for controlling output
    ///   - prompt: A closure that builds a Prompt using PromptBuilder
    ///   - onStream: A closure that handles each ResponseStream.Snapshot
    public init(
        session: Relay<LanguageModelSession>,
        options: GenerationOptions = GenerationOptions(),
        @PromptBuilder prompt: @escaping (In) -> Prompt,
        onStream: @escaping (GenerateSnapshot<Out>) async -> Void
    ) {
        self.session = session
        self.options = options
        self.promptBuilder = prompt
        self.streamHandler = onStream
    }
    
    /// Creates a new Generate step with a shared session via Relay
    /// - Parameters:
    ///   - session: A Relay to a shared LanguageModelSession
    ///   - options: Generation options for controlling output
    ///   - prompt: A closure that builds a Prompt using PromptBuilder
    public init(
        session: Relay<LanguageModelSession>,
        options: GenerationOptions = GenerationOptions(),
        @PromptBuilder prompt: @escaping (In) -> Prompt
    ) {
        self.session = session
        self.options = options
        self.promptBuilder = prompt
        self.streamHandler = nil
    }
    
    /// Creates a new Generate step with Relay (backward compatibility)
    /// - Parameters:
    ///   - session: A Relay to a shared LanguageModelSession
    ///   - options: Generation options for controlling output
    ///   - transform: A closure to transform the input to a string prompt
    public init(
        session: Relay<LanguageModelSession>,
        options: GenerationOptions = GenerationOptions(),
        transform: @escaping (In) -> String
    ) {
        self.session = session
        self.options = options
        self.promptBuilder = { input in Prompt(transform(input)) }
        self.streamHandler = nil
    }
    
    /// Creates a new Generate step with a shared session via Relay
    /// When Input conforms to PromptRepresentable, no prompt builder is needed
    /// - Parameters:
    ///   - session: A Relay to a shared LanguageModelSession
    ///   - options: Generation options for controlling output
    public init(
        session: Relay<LanguageModelSession>,
        options: GenerationOptions = GenerationOptions()
    ) where In: PromptRepresentable {
        self.session = session
        self.options = options
        self.promptBuilder = { input in input.promptRepresentation }
        self.streamHandler = nil
    }
    
    /// Creates a new Generate step with streaming support
    /// When Input conforms to PromptRepresentable
    /// - Parameters:
    ///   - session: A Relay to a shared LanguageModelSession
    ///   - options: Generation options for controlling output
    ///   - onStream: A closure that handles each ResponseStream.Snapshot
    public init(
        session: Relay<LanguageModelSession>,
        options: GenerationOptions = GenerationOptions(),
        onStream: @escaping (GenerateSnapshot<Out>) async -> Void
    ) where In: PromptRepresentable {
        self.session = session
        self.options = options
        self.promptBuilder = { input in input.promptRepresentation }
        self.streamHandler = onStream
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
            
            do {
                if let handler = streamHandler {
                    // Streaming mode - use streamResponse
                    span.addEvent("streaming_started")
                    var lastContent: Out?
                    
                    let responseStream = session.wrappedValue.streamResponse(
                        generating: Out.self,
                        includeSchemaInPrompt: true,
                        options: options
                    ) {
                        prompt
                    }
                    
                    for try await snapshot in responseStream {
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
                    let response = try await session.wrappedValue.respond(
                        generating: Out.self,
                        includeSchemaInPrompt: true,
                        options: options
                    ) {
                        prompt
                    }
                    
                    // Span is successful by default
                    return response.content
                }
            } catch {
                span.recordError(error)
                throw ModelError.generationFailed(error.localizedDescription)
            }
        }
    }
}

/// A step that generates string output using OpenFoundationModels
///
/// GenerateText supports both streaming and non-streaming modes for text generation.
///
/// Example usage (non-streaming):
/// ```swift
/// let step = GenerateText<String>(session: relay) { input in
///     Prompt("Generate a story about: \(input)")
/// }
/// let story = try await step.run("a brave knight")
/// ```
///
/// Example usage (streaming with Snapshot):
/// ```swift
/// var previousContent = ""
/// let step = GenerateText<String>(
///     session: relay,
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
///     session: relay,
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
///     session: relay,
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
    
    private let session: Relay<LanguageModelSession>
    private let options: GenerationOptions
    private let promptBuilder: (In) -> Prompt
    private let streamHandler: ((GenerateSnapshot<Output>) async -> Void)?
    
    /// Creates a new GenerateText step with streaming support
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
        self.session = session
        self.options = options
        self.promptBuilder = prompt
        self.streamHandler = onStream
    }
    
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
        self.session = session
        self.options = options
        self.promptBuilder = prompt
        self.streamHandler = nil
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
        self.session = session
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
        self.session = session
        self.options = options
        self.promptBuilder = { input in input.promptRepresentation }
        self.streamHandler = nil
    }
    
    /// Creates a new GenerateText step with streaming support
    /// When Input conforms to PromptRepresentable
    /// - Parameters:
    ///   - session: A Relay to a shared LanguageModelSession
    ///   - options: Generation options for controlling output
    ///   - onStream: A closure that handles each ResponseStream.Snapshot
    public init(
        session: Relay<LanguageModelSession>,
        options: GenerationOptions = GenerationOptions(),
        onStream: @escaping (GenerateSnapshot<Output>) async -> Void
    ) where In: PromptRepresentable {
        self.session = session
        self.options = options
        self.promptBuilder = { input in input.promptRepresentation }
        self.streamHandler = onStream
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
            
            do {
                if let handler = streamHandler {
                    // Streaming mode - use streamResponse
                    span.addEvent("streaming_started")
                    var lastContent: String = ""
                    
                    let responseStream = session.wrappedValue.streamResponse(
                        options: options
                    ) {
                        prompt
                    }
                    
                    for try await snapshot in responseStream {
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
                    let response = try await session.wrappedValue.respond(
                        options: options
                    ) {
                        prompt
                    }
                    
                    // Span is successful by default
                    return response.content
                }
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
