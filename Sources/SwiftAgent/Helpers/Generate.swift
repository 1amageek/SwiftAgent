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

// MARK: - GeneratedText

/// Represents generated text with both current chunk and accumulated content
public struct GeneratedText: Sendable {
    /// The latest chunk of text that was just generated
    public let chunk: String
    
    /// The accumulated text content so far
    public let accumulated: String
    
    /// Whether the generation is complete
    public let isComplete: Bool
    
    public init(chunk: String, accumulated: String, isComplete: Bool = false) {
        self.chunk = chunk
        self.accumulated = accumulated
        self.isComplete = isComplete
    }
}

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
/// Example usage (streaming):
/// ```swift
/// let step = Generate<String, BlogPost>(
///     session: relay,
///     prompt: { input in
///         Prompt("Write a blog post about: \(input)")
///     },
///     onStream: { post, rawContent in
///         print("Title: \(post.title)")
///         print("Content length: \(post.content.count)")
///         print("Is complete: \(rawContent.isComplete)")
///         
///         // Access raw JSON if needed
///         if let json = rawContent.jsonString {
///             print("Raw JSON length: \(json.count)")
///         }
///     }
/// )
/// let finalPost = try await step.run("Swift Concurrency")
/// ```
///
/// When using streaming, the `onStream` handler receives both the typed output
/// and the raw GeneratedContent for each update. The final complete result is
/// still returned by the `run` method.
public struct Generate<In: Sendable, Out: Sendable & Generable>: Step {
    
    public typealias Input = In
    public typealias Output = Out
    
    private let session: Relay<LanguageModelSession>
    private let promptBuilder: (In) -> Prompt
    private let streamHandler: ((Out, GeneratedContent) async -> Void)?
    
    /// Creates a new Generate step with streaming support
    /// - Parameters:
    ///   - session: A Relay to a shared LanguageModelSession
    ///   - prompt: A closure that builds a Prompt using PromptBuilder
    ///   - onStream: A closure that handles each streamed output with both typed content and raw GeneratedContent
    public init(
        session: Relay<LanguageModelSession>,
        @PromptBuilder prompt: @escaping (In) -> Prompt,
        onStream: @escaping (Out, GeneratedContent) async -> Void
    ) {
        self.session = session
        self.promptBuilder = prompt
        self.streamHandler = onStream
    }
    
    /// Creates a new Generate step with a shared session via Relay
    /// - Parameters:
    ///   - session: A Relay to a shared LanguageModelSession
    ///   - prompt: A closure that builds a Prompt using PromptBuilder
    public init(
        session: Relay<LanguageModelSession>,
        @PromptBuilder prompt: @escaping (In) -> Prompt
    ) {
        self.session = session
        self.promptBuilder = prompt
        self.streamHandler = nil
    }
    
    /// Creates a new Generate step with Relay (backward compatibility)
    /// - Parameters:
    ///   - session: A Relay to a shared LanguageModelSession
    ///   - transform: A closure to transform the input to a string prompt
    public init(
        session: Relay<LanguageModelSession>,
        transform: @escaping (In) -> String
    ) {
        self.session = session
        self.promptBuilder = { input in Prompt(transform(input)) }
        self.streamHandler = nil
    }
    
    /// Creates a new Generate step with a shared session via Relay
    /// When Input conforms to PromptRepresentable, no prompt builder is needed
    /// - Parameter session: A Relay to a shared LanguageModelSession
    public init(
        session: Relay<LanguageModelSession>
    ) where In: PromptRepresentable {
        self.session = session
        self.promptBuilder = { input in input.promptRepresentation }
        self.streamHandler = nil
    }
    
    /// Creates a new Generate step with streaming support
    /// When Input conforms to PromptRepresentable
    /// - Parameters:
    ///   - session: A Relay to a shared LanguageModelSession
    ///   - onStream: A closure that handles each streamed output with both typed content and raw GeneratedContent
    public init(
        session: Relay<LanguageModelSession>,
        onStream: @escaping (Out, GeneratedContent) async -> Void
    ) where In: PromptRepresentable {
        self.session = session
        self.promptBuilder = { input in input.promptRepresentation }
        self.streamHandler = onStream
    }
    
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
                        includeSchemaInPrompt: true
                    ) {
                        prompt
                    }
                    
                    for try await snapshot in responseStream {
                        lastContent = snapshot.content
                        // Call the user's stream handler with both typed content and raw GeneratedContent
                        await handler(snapshot.content, snapshot.rawContent)
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
                        includeSchemaInPrompt: true
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
/// Example usage (streaming - real-time display):
/// ```swift
/// let step = GenerateText<String>(
///     session: relay,
///     prompt: { input in
///         Prompt("Generate a story about: \(input)")
///     },
///     onStream: { generated in
///         print(generated.chunk, terminator: "")  // Display new chunk
///         
///         if generated.isComplete {
///             print("\n[Story complete: \(generated.accumulated.count) characters]")
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
///     onStream: { generated in
///         print("Progress: \(generated.accumulated.count) characters")
///         print("Latest chunk: \(generated.chunk.count) characters")
///         
///         // Show progress bar
///         let progress = min(generated.accumulated.count / 1000, 1.0)
///         updateProgressBar(progress)
///     }
/// )
/// let essay = try await step.run("AI")
/// ```
///
/// Example usage (streaming - UI updates with buffering):
/// ```swift
/// let step = GenerateText<String>(
///     session: relay,
///     prompt: { input in
///         Prompt("Explain: \(input)")
///     },
///     onStream: { generated in
///         await MainActor.run {
///             // Append only the new chunk
///             textView.append(generated.chunk)
///             
///             // Update status
///             statusLabel.text = "Generated: \(generated.accumulated.count) characters"
///         }
///     }
/// )
/// ```
///
/// When using streaming, the `onStream` handler receives a GeneratedText struct
/// containing both the latest chunk and the accumulated text. The complete text
/// is still returned by the `run` method.
public struct GenerateText<In: Sendable>: Step {
    
    public typealias Input = In
    public typealias Output = String
    
    private let session: Relay<LanguageModelSession>
    private let promptBuilder: (In) -> Prompt
    private let streamHandler: ((GeneratedText) async -> Void)?
    
    /// Creates a new GenerateText step with streaming support
    /// - Parameters:
    ///   - session: A Relay to a shared LanguageModelSession
    ///   - prompt: A closure that builds a Prompt using PromptBuilder
    ///   - onStream: A closure that handles each streamed text with chunk and accumulated content
    public init(
        session: Relay<LanguageModelSession>,
        @PromptBuilder prompt: @escaping (In) -> Prompt,
        onStream: @escaping (GeneratedText) async -> Void
    ) {
        self.session = session
        self.promptBuilder = prompt
        self.streamHandler = onStream
    }
    
    /// Creates a new GenerateText step with a shared session via Relay
    /// - Parameters:
    ///   - session: A Relay to a shared LanguageModelSession
    ///   - prompt: A closure that builds a Prompt using PromptBuilder
    public init(
        session: Relay<LanguageModelSession>,
        @PromptBuilder prompt: @escaping (In) -> Prompt
    ) {
        self.session = session
        self.promptBuilder = prompt
        self.streamHandler = nil
    }
    
    /// Creates a new GenerateText step with Relay (backward compatibility)
    /// - Parameters:
    ///   - session: A Relay to a shared LanguageModelSession
    ///   - transform: A closure to transform the input to a string prompt
    public init(
        session: Relay<LanguageModelSession>,
        transform: @escaping (In) -> String
    ) {
        self.session = session
        self.promptBuilder = { input in Prompt(transform(input)) }
        self.streamHandler = nil
    }
    
    /// Creates a new GenerateText step with a shared session via Relay
    /// When Input conforms to PromptRepresentable, no prompt builder is needed
    /// - Parameter session: A Relay to a shared LanguageModelSession
    public init(
        session: Relay<LanguageModelSession>
    ) where In: PromptRepresentable {
        self.session = session
        self.promptBuilder = { input in input.promptRepresentation }
        self.streamHandler = nil
    }
    
    /// Creates a new GenerateText step with streaming support
    /// When Input conforms to PromptRepresentable
    /// - Parameters:
    ///   - session: A Relay to a shared LanguageModelSession
    ///   - onStream: A closure that handles each streamed text with chunk and accumulated content
    public init(
        session: Relay<LanguageModelSession>,
        onStream: @escaping (GeneratedText) async -> Void
    ) where In: PromptRepresentable {
        self.session = session
        self.promptBuilder = { input in input.promptRepresentation }
        self.streamHandler = onStream
    }
    
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
                    var previousContent = ""
                    var accumulated = ""
                    
                    let responseStream = session.wrappedValue.streamResponse {
                        prompt
                    }
                    
                    for try await snapshot in responseStream {
                        let currentContent = snapshot.content
                        // Calculate the chunk (delta from previous content)
                        let chunk = String(currentContent.dropFirst(previousContent.count))
                        accumulated = currentContent
                        
                        // Call the user's stream handler with GeneratedText
                        await handler(GeneratedText(
                            chunk: chunk,
                            accumulated: accumulated,
                            isComplete: false
                        ))
                        
                        previousContent = currentContent
                    }
                    
                    // Send final completion signal
                    await handler(GeneratedText(
                        chunk: "",
                        accumulated: accumulated,
                        isComplete: true
                    ))
                    
                    span.addEvent("streaming_completed")
                    return accumulated
                    
                } else {
                    // Non-streaming mode - use respond
                    // Note: Tool execution happens internally in the LanguageModel implementation
                    // if tools are registered in the session. The model will handle tool calls
                    // automatically based on its implementation (e.g., OpenAI, Anthropic).
                    let response = try await session.wrappedValue.respond {
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