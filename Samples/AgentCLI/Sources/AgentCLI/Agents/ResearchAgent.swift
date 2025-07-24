//
//  ResearchAgent.swift
//  AgentCLI
//
//  Created by SwiftAgent Generator on 2025/01/17.
//

import Foundation
import SwiftAgent
import AgentTools
import OpenFoundationModels
import OpenFoundationModelsOpenAI

/// A research agent equipped with web browsing and file system capabilities
public struct ResearchAgent: Agent {
    let configuration: AgentConfiguration
    
    public init(configuration: AgentConfiguration) {
        self.configuration = configuration
    }
    
    public var body: some Step<String, String> {
        GenerateText<String>(
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
            tools: [
                URLFetchTool(),
                FileSystemTool(workingDirectory: FileManager.default.currentDirectoryPath),
                ExecuteCommandTool()
            ],
            instructions: Instructions("""
            You are a research assistant AI with access to web browsing, file system operations, and command execution tools.
            
            Available tools:
            - url_fetch: Fetch content from web URLs for research
            - filesystem: Read and write files, list directories
            - execute: Run command-line tools for system operations
            
            Use these tools when helpful to provide comprehensive research and analysis.
            Always verify information from multiple sources when possible.
            """)
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