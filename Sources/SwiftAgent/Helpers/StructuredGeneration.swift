//
//  StructuredGeneration.swift
//  SwiftAgent
//
//  Created by Norikazu Muramoto on 2025/01/16.
//

import Foundation
import OpenFoundationModels

/// A step that generates structured data using OpenFoundationModels' Generable protocol
public struct StructuredGenerationStep<Input: Sendable, Output: Sendable & Generable>: Step {
    
    public typealias Input = Input
    public typealias Output = Output
    
    private let session: LanguageModelSession
    private let transform: (Input) -> String
    private let schema: GenerationSchema
    
    /// Creates a new StructuredGenerationStep
    /// - Parameters:
    ///   - session: The LanguageModelSession to use
    ///   - schema: The generation schema for structured output
    ///   - transform: A closure to transform the input to a string prompt
    public init(
        session: LanguageModelSession,
        schema: GenerationSchema,
        transform: @escaping (Input) -> String
    ) {
        self.session = session
        self.schema = schema
        self.transform = transform
    }
    
    /// Creates a new StructuredGenerationStep with default SystemLanguageModel
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
        transform: @escaping (Input) -> String
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

/// A convenience step for generating JSON-structured data
public struct JSONGenerationStep<Input: Sendable, Output: Sendable & Codable>: Step {
    
    public typealias Input = Input
    public typealias Output = Output
    
    private let session: LanguageModelSession
    private let transform: (Input) -> String
    private let outputType: Output.Type
    
    /// Creates a new JSONGenerationStep
    /// - Parameters:
    ///   - outputType: The expected output type
    ///   - session: The LanguageModelSession to use
    ///   - transform: A closure to transform the input to a string prompt
    public init(
        outputType: Output.Type,
        session: LanguageModelSession,
        transform: @escaping (Input) -> String
    ) {
        self.outputType = outputType
        self.session = session
        self.transform = transform
    }
    
    /// Creates a new JSONGenerationStep with default SystemLanguageModel
    /// - Parameters:
    ///   - outputType: The expected output type
    ///   - tools: Tools to be used by the model
    ///   - guardrails: Guardrails for content safety
    ///   - instructions: Instructions for the model
    ///   - transform: A closure to transform the input to a string prompt
    public init(
        outputType: Output.Type,
        tools: [any OpenFoundationModels.Tool] = [],
        guardrails: LanguageModelSession.Guardrails? = nil,
        instructions: String? = nil,
        transform: @escaping (Input) -> String
    ) {
        self.outputType = outputType
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
            let response = try await session.respond(to: prompt)
            
            // Try to parse the response as JSON
            guard let data = response.content.data(using: .utf8) else {
                throw ModelError.invalidInput("Cannot convert response to data")
            }
            
            let decoder = JSONDecoder()
            return try decoder.decode(outputType, from: data)
        } catch {
            throw ModelError.generationFailed(error.localizedDescription)
        }
    }
}



/// A step that validates generated content against a schema
public struct SchemaValidationStep<T: Codable & Sendable>: Step {
    
    public typealias Input = String
    public typealias Output = T
    
    /// Creates a new SchemaValidationStep
    /// - Parameter type: The expected output type
    public init(type: T.Type) {
        // Empty init as we don't need schema anymore
    }
    
    public func run(_ input: Input) async throws -> Output {
        guard let data = input.data(using: .utf8) else {
            throw ModelError.invalidInput("Cannot convert input to data")
        }
        
        let decoder = JSONDecoder()
        do {
            return try decoder.decode(T.self, from: data)
        } catch {
            throw ModelError.generationFailed("Failed to decode structured data: \(error.localizedDescription)")
        }
    }
}

/// A convenience extension for creating generation steps
extension StructuredGenerationStep {
    
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
        transform: @escaping (Input) -> String
    ) -> StructuredGenerationStep<Input, T> {
        return StructuredGenerationStep<Input, T>(
            schema: T.generationSchema,
            tools: tools,
            guardrails: guardrails ?? .default,
            instructions: instructions,
            transform: transform
        )
    }
}