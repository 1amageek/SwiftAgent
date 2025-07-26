//
//  ReasoningAgent.swift
//  AgentCLI
//
//  Created by SwiftAgent Generator on 2025/01/17.
//

import Foundation
import SwiftAgent
import OpenFoundationModels
import OpenFoundationModelsOpenAI

/// A reasoning agent optimized for complex problem-solving using o1 models
public struct ReasoningAgent: Agent {
    let configuration: AgentConfiguration
    
    public init(configuration: AgentConfiguration) {
        self.configuration = configuration
    }
    
    public var body: some Step<String, String> {
        GenerateText<String>(
            session: createLanguageModelSession(),
            transform: { input in
                """
                Think step by step to solve this problem or answer this question.
                Break down complex problems into smaller components and reason through each step.
                
                Problem/Question: \(input)
                """
            }
        )
    }
    
    private func createLanguageModelSession() -> LanguageModelSession {
        return LanguageModelSession(
            model: createModel(),
            guardrails: .default,
            tools: [],
            instructions: Instructions("""
            You are a reasoning AI assistant specialized in complex problem-solving and analytical thinking.
            Take time to think through problems systematically:
            1. Break down complex problems into smaller parts
            2. Consider multiple approaches and perspectives
            3. Work through each step methodically
            4. Verify your reasoning at each stage
            5. Provide clear explanations of your thought process
            
            Focus on accuracy and thoroughness over speed.
            """)
        )
    }
    
    private func createModel() -> any LanguageModel {
        let modelName = configuration.model.lowercased()
        
        // Select appropriate reasoning model
        let model: OpenAIModel
        switch modelName {
        case "o1":
            model = .o1
        case "o1-pro":
            model = .o1Pro
        case "o3":
            model = .o3
        case "o3-pro":
            model = .o3Pro
        case "o4-mini":
            model = .o4Mini
        case "gpt-4o", "gpt-4o-mini", "gpt-4-turbo", "gpt-3.5-turbo":
            // For reasoning tasks, suggest using a reasoning model
            if configuration.verbose {
                print("Note: Reasoning agent works best with reasoning models (o1, o3, etc.). Using o4-mini for optimal reasoning performance.")
            }
            model = .o4Mini
        default:
            // Default to o4-mini for reasoning tasks
            if configuration.verbose {
                print("Reasoning agent works best with reasoning models. Using o4-mini for optimal reasoning performance.")
            }
            model = .o4Mini
        }
        
        let openAIConfig = OpenAIConfiguration(apiKey: configuration.apiKey)
        return OpenAILanguageModel(configuration: openAIConfig, model: model)
    }
}