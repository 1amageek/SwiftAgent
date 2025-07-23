//
//  AgentCommand.swift
//  SwiftAgent
//
//  Created by Assistant on 2025/01/11.
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
/// # Query with maximum steps
/// agent ask "Plan my vacation" 20
///
/// # Query with quiet mode
/// agent ask --quiet "Summarize this document"
/// ```

@main
struct AgentCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "agent",
        abstract: "AI Agent Command Line Tool",
        version: "1.0.0",
        subcommands: [Ask.self, Config.self]
    )
    
    @Flag(name: .shortAndLong, help: "Enable verbose logging")
    var verbose: Bool = false
    
    // メインコマンドの実装（サブコマンドなしの場合）
    mutating func run() async throws {
        if verbose {
            ConfigurationManager.shared.log("Starting interactive session")
        }
        
        print("Starting interactive AI agent session. Type 'exit' to quit.\n")
        _ = try await MainAgent().run("")
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
        
        mutating func run() async throws {
            guard !prompt.isEmpty else {
                throw ValidationError("Question cannot be empty")
            }
            
            if verbose {
                ConfigurationManager.shared.log("Processing query: \(prompt)")
            }
            
            let output = try await AskAgent().run(prompt)
            print(output)
        }
    }
}
