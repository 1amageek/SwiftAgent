//
//  main.swift
//  AgentCLI
//
//  Created by SwiftAgent Generator on 2025/01/17.
//

import Foundation
import ArgumentParser
import SwiftAgent
import AgentTools

/// A command-line interface for interacting with AI agents.
///
/// `AgentCommand` serves as the main entry point for the CLI application, providing
/// commands to interact with AI agents through the terminal.
///
/// Example usage:
/// ```bash
/// # Basic query
/// agent ask "What is the weather today?"
///
/// # Query with specific model
/// agent ask --model gpt-4o "Plan my vacation"
///
/// # Interactive session
/// agent
/// ```

@main
struct AgentCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "agent",
        abstract: "AI Agent Command Line Tool with OpenAI Support",
        version: "2.0.0",
        subcommands: [Ask.self]
    )
    
    @Flag(name: .shortAndLong, help: "Enable verbose logging")
    var verbose: Bool = false
    
    @Option(name: .long, help: "OpenAI API key (can also use OPENAI_API_KEY env var)")
    var apiKey: String?
    
    @Option(name: .long, help: "Model to use (gpt-4o, o1-preview, o1-mini, gpt-3.5-turbo)")
    var model: String = "gpt-4o"
    
    // メインコマンドの実装（サブコマンドなしの場合）
    mutating func run() async throws {
        let config = try loadConfiguration()
        
        if verbose {
            print("Starting interactive session with model: \(config.model)")
        }
        
        print("Starting interactive AI agent session. Type 'exit' to quit.\n")
        _ = try await MainAgent(configuration: config).run("")
    }
    
    private func loadConfiguration() throws -> AgentConfiguration {
        let apiKey = self.apiKey ?? ProcessInfo.processInfo.environment["OPENAI_API_KEY"]
        
        guard let apiKey = apiKey, !apiKey.isEmpty else {
            throw ValidationError("OpenAI API key is required. Set OPENAI_API_KEY environment variable or use --api-key option.")
        }
        
        return AgentConfiguration(
            apiKey: apiKey,
            model: model,
            verbose: verbose
        )
    }
    
    // Askサブコマンドの実装
    struct Ask: AsyncParsableCommand {
        static let configuration = CommandConfiguration(
            commandName: "ask",
            abstract: "Send a specific question to the agent for detailed analysis"
        )
        
        @Argument(help: "The question to analyze")
        var prompt: String
        
        @Flag(name: .shortAndLong, help: "Show only the final answer")
        var quiet: Bool = false
        
        @Flag(name: .shortAndLong, help: "Enable verbose logging")
        var verbose: Bool = false
        
        @Option(name: .long, help: "OpenAI API key (can also use OPENAI_API_KEY env var)")
        var apiKey: String?
        
        @Option(name: .long, help: "Model to use (gpt-4o, o1-preview, o1-mini, gpt-3.5-turbo)")
        var model: String = "gpt-4o"
        
        @Option(name: .long, help: "Agent type (basic, research, analysis, reasoning)")
        var agentType: String = "basic"
        
        mutating func run() async throws {
            guard !prompt.isEmpty else {
                throw ValidationError("Question cannot be empty")
            }
            
            let apiKey = self.apiKey ?? ProcessInfo.processInfo.environment["OPENAI_API_KEY"]
            
            guard let apiKey = apiKey, !apiKey.isEmpty else {
                throw ValidationError("OpenAI API key is required. Set OPENAI_API_KEY environment variable or use --api-key option.")
            }
            
            let config = AgentConfiguration(
                apiKey: apiKey,
                model: model,
                verbose: verbose
            )
            
            if verbose && !quiet {
                print("Processing query with \(model): \(prompt)")
            }
            
            let agent = try createAgent(type: agentType, configuration: config)
            let output = try await agent.run(prompt)
            
            if quiet {
                print(output)
            } else {
                print("\n--- Agent Response ---")
                print(output)
                print("--- End Response ---\n")
            }
        }
        
        private func createAgent(type: String, configuration: AgentConfiguration) throws -> any Step<String, String> {
            switch type.lowercased() {
            case "basic":
                return BasicChatAgent(configuration: configuration)
            case "research":
                return ResearchAgent(configuration: configuration)
            case "analysis":
                return AnalysisAgent(configuration: configuration)
            case "reasoning":
                return ReasoningAgent(configuration: configuration)
            default:
                throw ValidationError("Unknown agent type: \(type). Available types: basic, research, analysis, reasoning")
            }
        }
    }
}

/// Configuration structure for agent setup
public struct AgentConfiguration {
    let apiKey: String
    let model: String
    let verbose: Bool
}