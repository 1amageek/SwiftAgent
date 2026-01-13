//
//  ChatAgent.swift
//  AgentCLI
//
//  Created by SwiftAgent on 2025/01/17.
//

import Foundation
import SwiftAgent
import OpenFoundationModelsOpenAI

/// A conversational chat agent with streaming output.
///
/// Demonstrates:
/// - `@Session` for TaskLocal session propagation
/// - `GenerateText` with `@PromptBuilder`
/// - Streaming with `onStream` handler
/// - Simple step composition
public struct ChatAgent: Step {
    public typealias Input = String
    public typealias Output = String

    @Session var session: LanguageModelSession

    public init() {}

    public func run(_ input: String) async throws -> String {
        var result = ""

        let step = GenerateText<String>(
            session: session,
            prompt: { Prompt($0) },
            onStream: { snapshot in
                let content = snapshot.content
                if content.count > result.count {
                    let newContent = String(content.dropFirst(result.count))
                    print(newContent, terminator: "")
                    fflush(stdout)
                }
                result = content
            }
        )

        let output = try await step.run(input)
        print()
        return output
    }
}

/// Factory for creating chat sessions
public struct ChatSessionFactory {

    public static func createSession(configuration: AgentConfiguration) -> LanguageModelSession {
        configuration.createSession(
            instructions: Instructions {
                """
                You are a helpful AI assistant. Provide clear, accurate, and friendly responses.
                Be concise but thorough. Ask clarifying questions when needed.
                """
            }
        )
    }

    public static func createReasoningSession(configuration: AgentConfiguration) -> LanguageModelSession {
        let reasoningModel: OpenAIModel = configuration.model.isReasoningModel
            ? configuration.model
            : .o4Mini

        let config = AgentConfiguration(
            apiKey: configuration.apiKey,
            model: reasoningModel,
            verbose: configuration.verbose,
            workingDirectory: configuration.workingDirectory
        )

        return config.createSession(
            instructions: Instructions {
                """
                You are an analytical AI assistant specialized in complex reasoning.
                Think step by step through problems. Consider multiple perspectives.
                Verify your reasoning at each stage.
                """
            }
        )
    }
}

/// Interactive chat loop
public struct InteractiveChatAgent: Step {
    public typealias Input = String
    public typealias Output = String

    private let configuration: AgentConfiguration

    public init(configuration: AgentConfiguration) {
        self.configuration = configuration
    }

    public var body: some Step<String, String> {
        Loop { _ in
            WaitForInput(prompt: "You: ")
            Transform<String, String> { input in
                print("Assistant: ", terminator: "")
                return input
            }
            ChatAgent()
        }
        .session(ChatSessionFactory.createSession(configuration: configuration))
    }
}
