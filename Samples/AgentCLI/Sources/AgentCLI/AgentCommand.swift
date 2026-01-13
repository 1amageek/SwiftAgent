//
//  AgentCommand.swift
//  AgentCLI
//
//  Created by SwiftAgent on 2025/01/17.
//

import Foundation
import ArgumentParser
import SwiftAgent
import AgentTools
import OpenFoundationModelsOpenAI

@main
struct AgentCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "agent",
        abstract: "SwiftAgent CLI - AI Agent powered by OpenAI",
        version: "2.0.0",
        subcommands: [Chat.self, Code.self, Research.self],
        defaultSubcommand: Chat.self
    )
}

// MARK: - Shared Options

struct GlobalOptions: ParsableArguments {
    @Flag(name: .shortAndLong, help: "Enable verbose logging")
    var verbose: Bool = false

    @Option(name: .long, help: "OpenAI API key (or set OPENAI_API_KEY)")
    var apiKey: String?

    @Option(name: .shortAndLong, help: "Model to use (gpt-4.1, gpt-4.1-mini, gpt-4.1-nano, o3, o3-mini, o4-mini)")
    var model: String = "gpt-4.1"

    @Option(name: .shortAndLong, help: "Working directory for file operations")
    var workingDir: String?

    func createConfiguration() throws -> AgentConfiguration {
        let key = apiKey ?? ProcessInfo.processInfo.environment["OPENAI_API_KEY"]
        guard let apiKey = key, !apiKey.isEmpty else {
            throw ValidationError("OpenAI API key required. Set OPENAI_API_KEY or use --api-key")
        }

        return AgentConfiguration(
            apiKey: apiKey,
            model: OpenAIModel(model),
            verbose: verbose,
            workingDirectory: workingDir ?? FileManager.default.currentDirectoryPath
        )
    }
}

// MARK: - Chat Command

extension AgentCommand {
    struct Chat: AsyncParsableCommand {
        static let configuration = CommandConfiguration(
            commandName: "chat",
            abstract: "Start an interactive chat session"
        )

        @OptionGroup var options: GlobalOptions

        @Argument(help: "Initial message (optional, starts interactive mode if omitted)")
        var message: String?

        mutating func run() async throws {
            let config = try options.createConfiguration()

            if options.verbose {
                print("Starting chat with model: \(config.model)")
            }

            if let message = message {
                // Single message mode
                print("Assistant: ", terminator: "")
                let session = ChatSessionFactory.createSession(configuration: config)
                _ = try await ChatAgent()
                    .session(session)
                    .run(message)
            } else {
                // Interactive mode
                print("SwiftAgent Chat (type 'exit' to quit)")
                print("Model: \(config.model)")
                print("---")
                _ = try await InteractiveChatAgent(configuration: config).run("")
            }
        }
    }
}

// MARK: - Code Command

extension AgentCommand {
    struct Code: AsyncParsableCommand {
        static let configuration = CommandConfiguration(
            commandName: "code",
            abstract: "Coding assistant with file and command access"
        )

        @OptionGroup var options: GlobalOptions

        @Argument(help: "Coding task or question")
        var task: String?

        mutating func run() async throws {
            let config = try options.createConfiguration()

            if options.verbose {
                print("Starting coding assistant with model: \(config.model)")
                print("Working directory: \(config.workingDirectory)")
            }

            if let task = task {
                // Single task mode
                print("---")
                _ = try await CodingAgent(configuration: config).run(task)
            } else {
                // Interactive mode
                print("SwiftAgent Coding Assistant (type 'exit' to quit)")
                print("Model: \(config.model)")
                print("Working directory: \(config.workingDirectory)")
                print("---")
                _ = try await InteractiveCodingAgent(configuration: config).run("")
            }
        }
    }
}

// MARK: - Research Command

extension AgentCommand {
    struct Research: AsyncParsableCommand {
        static let configuration = CommandConfiguration(
            commandName: "research",
            abstract: "Research a topic with structured output"
        )

        @OptionGroup var options: GlobalOptions

        @Argument(help: "Research topic or question")
        var topic: String

        @Flag(name: .long, help: "Output raw JSON instead of formatted text")
        var json: Bool = false

        mutating func run() async throws {
            let config = try options.createConfiguration()

            if options.verbose {
                print("Starting research with model: \(config.model)")
            }

            if json {
                let result = try await ResearchAgent(configuration: config).run(topic)
                let encoder = JSONEncoder()
                encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
                let data = try encoder.encode(result)
                print(String(data: data, encoding: .utf8)!)
            } else {
                let output = try await ResearchAgentText(configuration: config).run(topic)
                print(output)
            }
        }
    }
}
