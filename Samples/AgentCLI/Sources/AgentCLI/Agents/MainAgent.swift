//
//  MainAgent.swift
//  AgentCLI
//
//  Created by SwiftAgent Generator on 2025/01/17.
//

import Foundation
import SwiftAgent
import OpenFoundationModels
import OpenFoundationModelsOpenAI

public struct MainAgent: Agent {
    let configuration: AgentConfiguration
    
    public init(configuration: AgentConfiguration) {
        self.configuration = configuration
    }

    public var body: some Step<String, String> {
        Loop { _ in
            WaitForInput(prompt: "You: ")
            GenerateText<String>(
                session: createLanguageModelSession(),
                transform: { input in
                    input
                }
            )
            .onOutput { message in
                print("Assistant: \(message)")
            }
        }
    }
    
    private func createLanguageModelSession() -> LanguageModelSession {
        return LanguageModelSession(
            model: createModel(),
            guardrails: .default,
            tools: [],
            instructions: Instructions("You are a helpful assistant. Have a conversation with the user.")
        )
    }
    
    private func createModel() -> any LanguageModel {
        switch configuration.model.lowercased() {
        case "gpt-4o":
            return OpenAIModelFactory.gpt4o(apiKey: configuration.apiKey)
        case "o1-preview":
            return OpenAIModelFactory.o3(apiKey: configuration.apiKey)
        case "o1-mini":
            return OpenAIModelFactory.o4Mini(apiKey: configuration.apiKey)
        case "gpt-3.5-turbo":
            return OpenAIModelFactory.gpt4oMini(apiKey: configuration.apiKey)
        default:
            if configuration.verbose {
                print("Unknown model '\(configuration.model)', falling back to gpt-4o")
            }
            return OpenAIModelFactory.gpt4o(apiKey: configuration.apiKey)
        }
    }
}
