//
//  ResearchAgent.swift
//  AgentCLI
//
//  Created by SwiftAgent on 2025/01/17.
//

import Foundation
import SwiftAgent
import AgentTools
import OpenFoundationModelsClaude

// MARK: - Claude Research Configuration

/// Configuration for the Claude-powered research agent
public struct ClaudeResearchConfiguration: Sendable {
    public let apiKey: String
    public let modelName: String
    public let verbose: Bool
    public let workingDirectory: String

    public init(
        apiKey: String,
        modelName: String = ClaudeLanguageModel.sonnet4_5,
        verbose: Bool = false,
        workingDirectory: String = FileManager.default.currentDirectoryPath
    ) {
        self.apiKey = apiKey
        self.modelName = modelName
        self.verbose = verbose
        self.workingDirectory = workingDirectory
    }

    public func createModel() -> ClaudeLanguageModel {
        let config = ClaudeConfiguration(apiKey: apiKey)
        return ClaudeLanguageModel(configuration: config, modelName: modelName)
    }

    public func createSession(
        tools: [any OpenFoundationModels.Tool] = [],
        instructions: Instructions
    ) -> LanguageModelSession {
        LanguageModelSession(
            model: createModel(),
            tools: tools,
            instructions: instructions
        )
    }
}

// MARK: - Research Agent

/// A research agent powered by Claude with comprehensive analysis capabilities.
///
/// Leverages Claude's strengths:
/// - Long context window (200K tokens) for comprehensive research
/// - Excellent structured analysis and synthesis
/// - Parallel tool execution for efficient data gathering
/// - Hypothesis development and confidence tracking
///
/// Demonstrates:
/// - `Pipeline` for multi-phase research workflow
/// - `Gate` for input validation
/// - `@Memory` for tracking research progress
/// - `Generate` for structured output with rich metadata
/// - Claude-optimized system prompts
public struct ResearchAgent: Step {
    public typealias Input = String
    public typealias Output = ResearchResult

    private let configuration: ClaudeResearchConfiguration

    /// URLs fetched during research
    @Memory var fetchedURLs: Set<String> = []

    /// Files analyzed during research
    @Memory var analyzedFiles: Set<String> = []

    /// Hypotheses developed during research
    @Memory var hypotheses: [String] = []

    public init(configuration: ClaudeResearchConfiguration) {
        self.configuration = configuration
    }

    public var body: some Step<String, ResearchResult> {
        Pipeline {
            // Phase 1: Validate and enhance query
            Gate<String, String> { query in
                let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
                guard trimmed.count >= 3 else {
                    return .block(reason: "Query too short (minimum 3 characters)")
                }
                return .pass(trimmed)
            }

            // Phase 2: Execute research with Claude
            ClaudeResearchStep(
                configuration: configuration,
                fetchedURLs: $fetchedURLs,
                analyzedFiles: $analyzedFiles,
                hypotheses: $hypotheses
            )
        }
    }
}

// MARK: - Structured Research Output

/// Comprehensive research result with rich metadata
@Generable
public struct ResearchResult: Sendable, Encodable {
    @Guide(description: "Executive summary of research findings in 2-3 sentences")
    public let summary: String

    @Guide(description: "List of key findings, each with supporting evidence")
    public let keyFindings: [KeyFinding]

    @Guide(description: "Sources used with reliability assessment")
    public let sources: [Source]

    @Guide(description: "Research methodology and approach taken")
    public let methodology: String

    @Guide(description: "Identified gaps or limitations in the research")
    public let limitations: [String]

    @Guide(description: "Suggested areas for further investigation")
    public let followUpQuestions: [String]

    @Guide(description: "Overall confidence level from 0.0 (no confidence) to 1.0 (high confidence)")
    public let confidence: Double
}

/// A key finding with supporting evidence
@Generable
public struct KeyFinding: Sendable, Encodable {
    @Guide(description: "The finding statement")
    public let finding: String

    @Guide(description: "Evidence supporting this finding")
    public let evidence: String

    @Guide(description: "Confidence in this specific finding from 0.0 to 1.0")
    public let confidence: Double
}

/// A source with reliability assessment
@Generable
public struct Source: Sendable, Encodable {
    @Guide(description: "Source title or description")
    public let title: String

    @Guide(description: "URL or file path")
    public let location: String

    @Guide(description: "Type of source: 'primary' (original data), 'secondary' (analysis of primary), or 'tertiary' (summary/compilation)")
    public let sourceType: String

    @Guide(description: "Reliability assessment: 'high' (verified, authoritative), 'medium' (generally reliable), 'low' (uncertain), or 'unknown'")
    public let reliability: String
}

// MARK: - Claude Research Step

/// Internal step that executes the research using Claude
private struct ClaudeResearchStep: Step {
    typealias Input = String
    typealias Output = ResearchResult

    let configuration: ClaudeResearchConfiguration
    let fetchedURLs: Relay<Set<String>>
    let analyzedFiles: Relay<Set<String>>
    let hypotheses: Relay<[String]>

    func run(_ query: String) async throws -> ResearchResult {
        let toolProvider = AgentToolsProvider(workingDirectory: configuration.workingDirectory)

        // Select tools optimized for research tasks
        let tools: [any Tool] = [
            toolProvider.tool(named: "WebFetch")!,  // Fetch known URLs
            toolProvider.tool(named: "Read")!,       // Read local files
            toolProvider.tool(named: "Grep")!,       // Search file contents
            toolProvider.tool(named: "Glob")!,       // Find files by pattern
        ]

        let session = configuration.createSession(
            tools: tools,
            instructions: Instructions {
                claudeResearchSystemPrompt
            }
        )

        if configuration.verbose {
            print("Research Query: \(query)")
            print("Model: \(configuration.modelName)")
            print("---")
        }

        print("Researching: \(query)")
        print("Analyzing and synthesizing findings...")
        print("---")

        // Use streaming mode with structured output
        let step = Generate<String, ResearchResult>(
            session: session,
            prompt: {
                Prompt(researchPrompt(for: $0))
            },
            onStream: { _ in
                // Progress indicator
                print(".", terminator: "")
                fflush(stdout)
            }
        )

        let result = try await step.run(query)
        print("\nResearch complete.")

        return result
    }

    /// Claude-optimized system prompt for research tasks
    private var claudeResearchSystemPrompt: String {
        """
        You are an expert research analyst with access to web fetching and file analysis tools.

        <core_capabilities>
        Your role is to conduct thorough, methodical research and provide well-structured findings with clear evidence and confidence assessments.
        </core_capabilities>

        <working_directory>
        Your file operations are restricted to: \(configuration.workingDirectory)
        All file paths must be within this directory. Use absolute paths or paths relative to this directory.
        Do NOT use paths like "../../" that would escape this directory.
        </working_directory>

        <available_tools>
        - WebFetch: Retrieve content from specific URLs. Use when you have exact URLs to investigate.
        - Read: Read local files. Paths must be within the working directory. Use absolute paths.
        - Grep: Search for patterns in files. Use regex patterns to find relevant content.
        - Glob: Find files matching patterns. Use to discover relevant files before reading them.

        <research_methodology>
        1. PLAN: Before gathering data, formulate initial hypotheses about what you expect to find.
        2. GATHER: Use tools efficiently. When multiple sources are needed, invoke tools in parallel when possible.
        3. ANALYZE: Evaluate each source's reliability. Cross-reference findings across sources.
        4. SYNTHESIZE: Combine findings into coherent conclusions. Note where sources agree or conflict.
        5. ASSESS: Provide honest confidence levels. Lower confidence when evidence is limited or conflicting.
        </research_methodology>

        <parallel_tool_use>
        For maximum efficiency, when you need to fetch multiple URLs or read multiple files, invoke all relevant tools simultaneously rather than sequentially. This significantly speeds up research.
        </parallel_tool_use>

        <confidence_calibration>
        - 0.9-1.0: Multiple high-quality sources strongly agree
        - 0.7-0.9: Good evidence from reliable sources with minor gaps
        - 0.5-0.7: Moderate evidence, some uncertainty or conflicting information
        - 0.3-0.5: Limited evidence, significant uncertainty
        - 0.0-0.3: Minimal evidence, mostly speculation
        </confidence_calibration>

        <output_quality>
        - Be specific and cite evidence for each finding
        - Distinguish between facts and inferences
        - Acknowledge limitations honestly
        - Suggest concrete follow-up questions for gaps
        </output_quality>
        """
    }

    /// Generate the research prompt for a given query
    private func researchPrompt(for query: String) -> String {
        """
        Research the following topic thoroughly and provide comprehensive, structured findings.

        <research_query>
        \(query)
        </research_query>

        <instructions>
        1. First, consider what sources might be relevant (web resources, local files, etc.)
        2. Gather information from multiple sources when possible
        3. Analyze and cross-reference the information
        4. Synthesize your findings into a structured response
        5. Be explicit about your confidence level and any limitations
        </instructions>

        Provide your findings in the requested structured format.
        """
    }
}

// MARK: - Text Output Wrapper

/// Wrapper that converts ResearchResult to formatted text output
public struct ResearchAgentText: Step {
    public typealias Input = String
    public typealias Output = String

    private let agent: ResearchAgent

    public init(configuration: ClaudeResearchConfiguration) {
        self.agent = ResearchAgent(configuration: configuration)
    }

    public func run(_ input: String) async throws -> String {
        let result = try await agent.run(input)
        return formatResult(result)
    }

    private func formatResult(_ result: ResearchResult) -> String {
        var output = """
        ## Executive Summary
        \(result.summary)

        ## Key Findings
        """

        for (index, finding) in result.keyFindings.enumerated() {
            let confidencePercent = Int(finding.confidence * 100)
            output += """

            ### \(index + 1). \(finding.finding)
            - **Evidence**: \(finding.evidence)
            - **Confidence**: \(confidencePercent)%
            """
        }

        output += "\n\n## Methodology\n\(result.methodology)"

        output += "\n\n## Sources"
        for source in result.sources {
            let reliabilityBadge = reliabilityEmoji(source.reliability)
            output += "\n- \(reliabilityBadge) [\(source.title)](\(source.location)) (\(source.sourceType), \(source.reliability) reliability)"
        }

        if !result.limitations.isEmpty {
            output += "\n\n## Limitations"
            for limitation in result.limitations {
                output += "\n- \(limitation)"
            }
        }

        if !result.followUpQuestions.isEmpty {
            output += "\n\n## Suggested Follow-up Questions"
            for question in result.followUpQuestions {
                output += "\n- \(question)"
            }
        }

        output += "\n\n---\n**Overall Confidence**: \(Int(result.confidence * 100))%"

        return output
    }

    private func reliabilityEmoji(_ reliability: String) -> String {
        switch reliability {
        case "high": return "[H]"
        case "medium": return "[M]"
        case "low": return "[L]"
        default: return "[?]"
        }
    }
}
