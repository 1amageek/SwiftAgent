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
        StringModelStep<String>(
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
        
        // Prefer o1 models for reasoning tasks
        if modelName == "o1-preview" || modelName == "o1-mini" {
            switch modelName {
            case "o1-preview":
                return OpenAIModelFactory.o3(apiKey: configuration.apiKey)
            case "o1-mini":
                return OpenAIModelFactory.o4Mini(apiKey: configuration.apiKey)
            default:
                break
            }
        }
        
        // Fallback to o1-mini if using other models
        if configuration.verbose {
            print("Reasoning agent works best with o1 models. Using o1-mini for optimal reasoning performance.")
        }
        return OpenAIModelFactory.o4Mini(apiKey: configuration.apiKey)
    }
}