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
                ReadTool(workingDirectory: FileManager.default.currentDirectoryPath),
                WriteTool(workingDirectory: FileManager.default.currentDirectoryPath),
                ExecuteCommandTool()
            ],
            instructions: Instructions("""
            You are a research assistant AI with access to web browsing, file system operations, and command execution tools.
            
            Available tools:
            - url_fetch: Fetch content from web URLs for research
            - read: Read file contents with line numbers
            - write: Write content to files
            - execute: Run command-line tools for system operations
            
            Use these tools when helpful to provide comprehensive research and analysis.
            Always verify information from multiple sources when possible.
            """)
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