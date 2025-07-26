//
//  ModelStep.swift
//  SwiftAgent
//
//  Created by Norikazu Muramoto on 2025/01/16.
//

import Foundation
import OpenFoundationModels

/// A step that integrates OpenFoundationModels' LanguageModelSession with SwiftAgent
public struct Generate<In: Sendable, Out: Sendable & Generable>: Step {
    
    public typealias Input = In
    public typealias Output = Out
    
    private let session: LanguageModelSession
    private let transform: (In) -> String
    
    /// Creates a new Generate step
    /// - Parameters:
    ///   - session: The LanguageModelSession to use
    ///   - transform: A closure to transform the input to a string prompt
    public init(
        session: LanguageModelSession,
        transform: @escaping (In) -> String
    ) {
        self.session = session
        self.transform = transform
    }
    
    
    /// Creates a new Generate step with default SystemLanguageModel
    /// - Parameters:
    ///   - tools: Tools to be used by the model
    ///   - guardrails: Guardrails for content safety
    ///   - instructions: Instructions for the model
    ///   - transform: A closure to transform the input to a string prompt
    public init(
        tools: [any OpenFoundationModels.Tool] = [],
        guardrails: LanguageModelSession.Guardrails? = nil,
        instructions: String? = nil,
        transform: @escaping (In) -> String
    ) {
        self.session = LanguageModelSession(
            model: SystemLanguageModel.default,
            guardrails: guardrails ?? .default,
            tools: tools,
            instructions: instructions.map { Instructions($0) }
        )
        self.transform = transform
    }
    
    public func run(_ input: In) async throws -> Out {
        let prompt = transform(input)
        
        do {
            let response = try await session.respond(
                generating: Out.self,
                includeSchemaInPrompt: true
            ) {
                Prompt(prompt)
            }
            return response.content
        } catch {
            throw ModelError.generationFailed(error.localizedDescription)
        }
    }
}

/// A step that generates string output using OpenFoundationModels
public struct GenerateText<In: Sendable>: Step {
    
    public typealias Input = In
    public typealias Output = String
    
    private let session: LanguageModelSession
    private let transform: (In) -> String
    
    /// Creates a new GenerateText step
    /// - Parameters:
    ///   - session: The LanguageModelSession to use
    ///   - transform: A closure to transform the input to a string prompt
    public init(
        session: LanguageModelSession,
        transform: @escaping (In) -> String
    ) {
        self.session = session
        self.transform = transform
    }
    
    
    /// Creates a new GenerateText step with default SystemLanguageModel
    /// - Parameters:
    ///   - tools: Tools to be used by the model
    ///   - guardrails: Guardrails for content safety
    ///   - instructions: Instructions for the model
    ///   - transform: A closure to transform the input to a string prompt
    public init(
        tools: [any OpenFoundationModels.Tool] = [],
        guardrails: LanguageModelSession.Guardrails? = nil,
        instructions: String? = nil,
        transform: @escaping (In) -> String
    ) {
        self.session = LanguageModelSession(
            model: SystemLanguageModel.default,
            guardrails: guardrails ?? .default,
            tools: tools,
            instructions: instructions.map { Instructions($0) }
        )
        self.transform = transform
    }
    
    public func run(_ input: In) async throws -> String {
        let prompt = transform(input)
        
        do {
            let response = try await session.respond {
                Prompt(prompt)
            }
            return response.content
        } catch {
            throw ModelError.generationFailed(error.localizedDescription)
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