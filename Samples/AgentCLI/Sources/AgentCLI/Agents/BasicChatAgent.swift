//
//  BasicChatAgent.swift
//  AgentCLI
//
//  Created by SwiftAgent Generator on 2025/01/17.
//

import Foundation
import SwiftAgent
import OpenFoundationModels
import OpenFoundationModelsOpenAI

/// A basic chat agent that provides simple conversational AI capabilities
public struct BasicChatAgent: Agent {
    let configuration: AgentConfiguration
    
    public init(configuration: AgentConfiguration) {
        self.configuration = configuration
    }
    
    public var body: some Step<String, String> {
        StringModelStep<String>(
            session: createLanguageModelSession(),
            transform: { input in
                input
            }
        )
    }
    
    private func createLanguageModelSession() -> LanguageModelSession {
        return LanguageModelSession(
            model: createModel(),
            guardrails: .default,
            tools: [],
            instructions: Instructions("""
            You are a helpful AI assistant. Provide clear, accurate, and friendly responses to user questions.
            Be concise but informative, and maintain a conversational tone.
            """)
        )
    }
    
    private func createModel() -> any LanguageModel {
        switch configuration.model.lowercased() {
        case "gpt-4o":
            return OpenAIModelFactory.gpt4o(apiKey: configuration.apiKey)
        default:
            if configuration.verbose {
                print("Unknown model '\(configuration.model)', falling back to gpt-4o")
            }
            return OpenAIModelFactory.gpt4o(apiKey: configuration.apiKey)
        }
    }
}
