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

/// A step that integrates OpenFoundationModels' LanguageModelSession with SwiftAgent
public struct Generate<In: Sendable, Out: Sendable & Generable>: Step {
    
    public typealias Input = In
    public typealias Output = Out
    
    private let session: Relay<LanguageModelSession>
    private let promptBuilder: (In) -> Prompt
    
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
    }
    
    public func run(_ input: In) async throws -> Out {
        try await withSpan(
            "Generate.\(Out.self)",
            ofKind: .client
        ) { span in
            // Set basic attributes for LLM call
            span.attributes[SwiftAgentSpanAttributes.stepType] = "LLMGeneration"
            
            // Build prompt
            let prompt = promptBuilder(input)
            span.addEvent("prompt_generated")
            
            do {
                let response = try await session.wrappedValue.respond(
                    generating: Out.self,
                    includeSchemaInPrompt: true
                ) {
                    prompt
                }
                
                // Span is successful by default
                return response.content
            } catch {
                span.recordError(error)
                throw ModelError.generationFailed(error.localizedDescription)
            }
        }
    }
}

/// A step that generates string output using OpenFoundationModels
public struct GenerateText<In: Sendable>: Step {
    
    public typealias Input = In
    public typealias Output = String
    
    private let session: Relay<LanguageModelSession>
    private let promptBuilder: (In) -> Prompt
    
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
    }
    
    public func run(_ input: In) async throws -> String {
        try await withSpan(
            "GenerateText",
            ofKind: .client
        ) { span in
            // Set basic attributes for LLM call
            span.attributes[SwiftAgentSpanAttributes.stepType] = "LLMTextGeneration"
            
            // Build prompt
            let prompt = promptBuilder(input)
            span.addEvent("prompt_generated")
            
            do {
                let response = try await session.wrappedValue.respond {
                    prompt
                }
                
                // Span is successful by default
                return response.content
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