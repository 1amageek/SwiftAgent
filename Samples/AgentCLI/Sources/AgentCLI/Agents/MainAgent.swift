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
        let model: OpenAIModel
        switch configuration.model.lowercased() {
        case "gpt-4o":
            model = .gpt4o
        case "gpt-4o-mini":
            model = .gpt4oMini
        case "gpt-4-turbo":
            model = .gpt4Turbo
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
        case "gpt-3.5-turbo": // Map legacy name to gpt-4o-mini
            model = .gpt4oMini
        default:
            if configuration.verbose {
                print("Unknown model '\(configuration.model)', falling back to gpt-4o")
            }
            model = .gpt4o
        }
        let openAIConfig = OpenAIConfiguration(apiKey: configuration.apiKey)
        return OpenAILanguageModel(configuration: openAIConfig, model: model)
    }
}
