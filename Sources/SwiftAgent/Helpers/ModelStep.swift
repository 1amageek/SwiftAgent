//
//  ModelStep.swift
//  SwiftAgent
//
//  Created by Norikazu Muramoto on 2025/01/16.
//

import Foundation
import OpenFoundationModels

/// A step that integrates OpenFoundationModels' LanguageModelSession with SwiftAgent
public struct ModelStep<Input: Sendable, Output: Sendable & Generable>: Step {
    
    public typealias Input = Input
    public typealias Output = Output
    
    private let session: LanguageModelSession
    private let transform: (Input) -> String
    
    /// Creates a new ModelStep
    /// - Parameters:
    ///   - session: The LanguageModelSession to use
    ///   - transform: A closure to transform the input to a string prompt
    public init(
        session: LanguageModelSession,
        transform: @escaping (Input) -> String
    ) {
        self.session = session
        self.transform = transform
    }
    
    /// Creates a new ModelStep with default SystemLanguageModel
    /// - Parameters:
    ///   - tools: Tools to be used by the model
    ///   - guardrails: Guardrails for content safety
    ///   - instructions: Instructions for the model
    ///   - transform: A closure to transform the input to a string prompt
    public init(
        tools: [any OpenFoundationModels.Tool] = [],
        guardrails: LanguageModelSession.Guardrails? = nil,
        instructions: String? = nil,
        transform: @escaping (Input) -> String
    ) {
        self.session = LanguageModelSession(
            model: SystemLanguageModel.default,
            guardrails: guardrails ?? .default,
            tools: tools,
            instructions: instructions.map { Instructions($0) }
        )
        self.transform = transform
    }
    
    public func run(_ input: Input) async throws -> Output {
        let prompt = transform(input)
        
        do {
            let response = try await session.respond(
                generating: Output.self,
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
public struct StringModelStep<Input: Sendable>: Step {
    
    public typealias Input = Input
    public typealias Output = String
    
    private let session: LanguageModelSession
    private let transform: (Input) -> String
    
    /// Creates a new StringModelStep
    /// - Parameters:
    ///   - session: The LanguageModelSession to use
    ///   - transform: A closure to transform the input to a string prompt
    public init(
        session: LanguageModelSession,
        transform: @escaping (Input) -> String
    ) {
        self.session = session
        self.transform = transform
    }
    
    /// Creates a new StringModelStep with default SystemLanguageModel
    /// - Parameters:
    ///   - tools: Tools to be used by the model
    ///   - guardrails: Guardrails for content safety
    ///   - instructions: Instructions for the model
    ///   - transform: A closure to transform the input to a string prompt
    public init(
        tools: [any OpenFoundationModels.Tool] = [],
        guardrails: LanguageModelSession.Guardrails? = nil,
        instructions: String? = nil,
        transform: @escaping (Input) -> String
    ) {
        self.session = LanguageModelSession(
            model: SystemLanguageModel.default,
            guardrails: guardrails ?? .default,
            tools: tools,
            instructions: instructions.map { Instructions($0) }
        )
        self.transform = transform
    }
    
    public func run(_ input: Input) async throws -> Output {
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