//
//  GenerateJSON.swift
//  SwiftAgent
//
//  Created by Norikazu Muramoto on 2025/01/16.
//

import Foundation
import OpenFoundationModels

/// A convenience step for generating JSON-structured data
public struct GenerateJSON<In: Sendable, Out: Sendable & Codable>: Step {
    
    public typealias Input = In
    public typealias Output = Out
    
    private let session: LanguageModelSession
    private let transform: (In) -> String
    private let outputType: Out.Type
    
    /// Creates a new GenerateJSON
    /// - Parameters:
    ///   - outputType: The expected output type
    ///   - session: The LanguageModelSession to use
    ///   - transform: A closure to transform the input to a string prompt
    public init(
        outputType: Out.Type,
        session: LanguageModelSession,
        transform: @escaping (In) -> String
    ) {
        self.outputType = outputType
        self.session = session
        self.transform = transform
    }
    
    /// Creates a new GenerateJSON with default SystemLanguageModel
    /// - Parameters:
    ///   - outputType: The expected output type
    ///   - tools: Tools to be used by the model
    ///   - guardrails: Guardrails for content safety
    ///   - instructions: Instructions for the model
    ///   - transform: A closure to transform the input to a string prompt
    public init(
        outputType: Out.Type,
        tools: [any OpenFoundationModels.Tool] = [],
        guardrails: LanguageModelSession.Guardrails? = nil,
        instructions: String? = nil,
        transform: @escaping (In) -> String
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
    
    public func run(_ input: In) async throws -> Out {
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