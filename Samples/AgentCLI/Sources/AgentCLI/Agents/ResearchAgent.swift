//
//  ResearchAgent.swift
//  AgentCLI
//
//  Created by SwiftAgent on 2025/01/17.
//

import Foundation
import SwiftAgent
import AgentTools

/// A research agent with web fetching, file reading, and structured output.
///
/// Demonstrates:
/// - `Pipeline` for step composition
/// - `Gate` for input validation and output formatting
/// - `@Memory` for tracking research progress
/// - `Generate` for structured output
/// - Tool integration (WebFetch, Read, Grep, Glob)
public struct ResearchAgent: Step {
    public typealias Input = String
    public typealias Output = ResearchResult

    private let configuration: AgentConfiguration

    /// URLs visited during research
    @Memory var visitedURLs: Set<String> = []

    /// Files read during research
    @Memory var readFiles: Set<String> = []

    public init(configuration: AgentConfiguration) {
        self.configuration = configuration
    }

    public var body: some Step<String, ResearchResult> {
        Pipeline {
            // Validate input
            Gate<String, String> { query in
                let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
                guard trimmed.count >= 3 else {
                    return .block(reason: "Query too short (minimum 3 characters)")
                }
                return .pass(trimmed)
            }

            // Perform research
            ResearchStep(
                configuration: configuration,
                visitedURLs: $visitedURLs,
                readFiles: $readFiles
            )
        }
    }
}

/// Structured research result
@Generable
public struct ResearchResult: Sendable, Encodable {
    @Guide(description: "A concise summary of the research findings")
    public let summary: String

    @Guide(description: "Key points discovered during research")
    public let keyFindings: [String]

    @Guide(description: "Sources used in the research")
    public let sources: [String]

    @Guide(description: "Confidence level from 0.0 to 1.0")
    public let confidence: Double
}

/// Internal research step
private struct ResearchStep: Step {
    typealias Input = String
    typealias Output = ResearchResult

    let configuration: AgentConfiguration
    let visitedURLs: Relay<Set<String>>
    let readFiles: Relay<Set<String>>

    func run(_ query: String) async throws -> ResearchResult {
        let toolProvider = AgentToolsProvider(workingDirectory: configuration.workingDirectory)
        let tools: [any Tool] = [
            toolProvider.tool(named: "WebFetch")!,
            toolProvider.tool(named: "Read")!,
            toolProvider.tool(named: "Grep")!,
            toolProvider.tool(named: "Glob")!,
        ]

        let session = configuration.createSession(
            tools: tools,
            instructions: Instructions {
                """
                You are a research assistant. Gather information from available sources.

                Available tools:
                - WebFetch: Fetch content from URLs
                - Read: Read local files
                - Grep: Search file contents
                - Glob: Find files by pattern

                Guidelines:
                - Use multiple sources when possible
                - Verify information across sources
                - Note the confidence level of your findings
                - Cite your sources clearly
                """
            }
        )

        print("Researching: \(query)")
        print("---")

        var streamedContent = ""
        let step = Generate<String, ResearchResult>(
            session: session,
            prompt: {
                Prompt("Research the following topic and provide structured findings: \($0)")
            },
            onStream: { snapshot in
                let json = snapshot.rawContent.jsonString
                if json.count > streamedContent.count {
                    streamedContent = json
                    print("\rGenerating research report...", terminator: "")
                    fflush(stdout)
                }
            }
        )

        let result = try await step.run(query)
        print("\rResearch complete.                    ")

        return result
    }
}

// MARK: - Text Output Wrapper

/// Wrapper that converts ResearchResult to formatted text output
public struct ResearchAgentText: Step {
    public typealias Input = String
    public typealias Output = String

    private let agent: ResearchAgent

    public init(configuration: AgentConfiguration) {
        self.agent = ResearchAgent(configuration: configuration)
    }

    public func run(_ input: String) async throws -> String {
        let result = try await agent.run(input)
        return formatResult(result)
    }

    private func formatResult(_ result: ResearchResult) -> String {
        var output = """
        ## Research Summary
        \(result.summary)

        ## Key Findings
        """

        for (index, finding) in result.keyFindings.enumerated() {
            output += "\n\(index + 1). \(finding)"
        }

        output += "\n\n## Sources"
        for source in result.sources {
            output += "\n- \(source)"
        }

        output += "\n\n## Confidence: \(Int(result.confidence * 100))%"

        return output
    }
}
