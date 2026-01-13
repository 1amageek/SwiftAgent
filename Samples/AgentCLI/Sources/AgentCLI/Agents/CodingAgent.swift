//
//  CodingAgent.swift
//  AgentCLI
//
//  Created by SwiftAgent on 2025/01/17.
//

import Foundation
import SwiftAgent
import AgentTools

/// A coding assistant agent with file operations, command execution, and task tracking.
///
/// Demonstrates:
/// - `@Memory` for state sharing between steps
/// - `@Session` for TaskLocal session propagation
/// - `GenerateText` with streaming
/// - `AgentTools` integration (Read, Write, Edit, Bash, Git)
/// - `Pipeline` and `Gate` for flow control
public struct CodingAgent: Step {
    public typealias Input = String
    public typealias Output = String

    private let configuration: AgentConfiguration

    /// Tracks completed tasks during the session
    @Memory var completedTasks: [String] = []

    /// Tracks files modified during the session
    @Memory var modifiedFiles: Set<String> = []

    public init(configuration: AgentConfiguration) {
        self.configuration = configuration
    }

    public var body: some Step<String, String> {
        Pipeline {
            // Entry gate: validate input
            Gate<String, String> { input in
                guard !input.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                    return .block(reason: "Empty input")
                }
                return .pass(input)
            }

            // Main processing with streaming
            CodingStep(
                configuration: configuration,
                completedTasks: $completedTasks,
                modifiedFiles: $modifiedFiles
            )

            // Exit gate: format output
            Gate<String, String> { output in
                .pass(output.trimmingCharacters(in: .whitespacesAndNewlines))
            }
        }
    }
}

/// Internal step that performs the actual coding assistance
private struct CodingStep: Step {
    typealias Input = String
    typealias Output = String

    let configuration: AgentConfiguration
    let completedTasks: Relay<[String]>
    let modifiedFiles: Relay<Set<String>>

    func run(_ input: String) async throws -> String {
        let toolProvider = AgentToolsProvider(workingDirectory: configuration.workingDirectory)
        let tools = toolProvider.allTools()

        let session = configuration.createSession(
            tools: tools,
            instructions: Instructions {
                """
                You are an expert coding assistant with access to file system and command execution tools.

                Available tools:
                - Read: Read file contents
                - Write: Create or overwrite files
                - Edit: Make precise edits to existing files
                - Glob: Find files by pattern
                - Grep: Search file contents
                - Bash: Execute shell commands
                - Git: Perform git operations

                Guidelines:
                - Always read files before editing them
                - Use Edit for small changes, Write for new files or complete rewrites
                - Explain your changes clearly
                - Follow best practices for the language you're working with
                """
            }
        )

        var result = ""
        let step = GenerateText<String>(
            session: session,
            prompt: { Prompt($0) },
            onStream: { snapshot in
                // Stream output to console
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
        print() // Newline after streaming

        // Track the task
        completedTasks.append(input.prefix(50).description)

        return output
    }
}

// MARK: - Interactive Mode

/// Interactive coding session with continuous input
public struct InteractiveCodingAgent: Step {
    public typealias Input = String
    public typealias Output = String

    private let configuration: AgentConfiguration

    @Memory var history: [String] = []

    public init(configuration: AgentConfiguration) {
        self.configuration = configuration
    }

    public var body: some Step<String, String> {
        Loop { _ in
            WaitForInput(prompt: "You: ")
            CodingAgent(configuration: configuration)
        }
    }
}
