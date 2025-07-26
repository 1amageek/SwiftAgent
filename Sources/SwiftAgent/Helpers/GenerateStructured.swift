//
//  GenerateStructured.swift
//  SwiftAgent
//
//  Created by Norikazu Muramoto on 2025/01/16.
//

import Foundation
import OpenFoundationModels

/// A step that generates structured data using OpenFoundationModels' Generable protocol
public struct GenerateStructured<In: Sendable, Out: Sendable & Generable>: Step {
    
    public typealias Input = In
    public typealias Output = Out
    
    private let session: LanguageModelSession
    private let transform: (In) -> String
    private let schema: GenerationSchema
    
    /// Creates a new GenerateStructured
    /// - Parameters:
    ///   - session: The LanguageModelSession to use
    ///   - schema: The generation schema for structured output
    ///   - transform: A closure to transform the input to a string prompt
    public init(
        session: LanguageModelSession,
        schema: GenerationSchema,
        transform: @escaping (In) -> String
    ) {
        self.session = session
        self.schema = schema
        self.transform = transform
    }
    
    /// Creates a new GenerateStructured with default SystemLanguageModel
    /// - Parameters:
    ///   - schema: The generation schema for structured output
    ///   - tools: Tools to be used by the model
    ///   - guardrails: Guardrails for content safety
    ///   - instructions: Instructions for the model
    ///   - transform: A closure to transform the input to a string prompt
    public init(
        schema: GenerationSchema,
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
        self.schema = schema
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

/// A convenience extension for creating generation steps
extension GenerateStructured {
    
    /// Creates a generation step for a specific Generable type
    /// - Parameters:
    ///   - type: The output type conforming to Generable
    ///   - tools: Tools to be used by the model
    ///   - guardrails: Guardrails for content safety
    ///   - instructions: Instructions for the model
    ///   - transform: A closure to transform the input to a string prompt
    /// - Returns: A configured FoundationModelGenerationStep
    public static func generate<T: Generable>(
        type: T.Type,
        tools: [any OpenFoundationModels.Tool] = [],
        guardrails: LanguageModelSession.Guardrails? = nil,
        instructions: String? = nil,
        transform: @escaping (In) -> String
    ) -> GenerateStructured<In, T> {
        return GenerateStructured<In, T>(
            schema: T.generationSchema,
            tools: tools,
            guardrails: guardrails ?? .default,
            instructions: instructions,
            transform: transform
        )
    }
}