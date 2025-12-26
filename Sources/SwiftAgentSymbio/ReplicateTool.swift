// MARK: - ReplicateTool
// Tool for LLM to spawn SubAgents when tasks require parallelization

import Foundation
import OpenFoundationModels
import SwiftAgent

// MARK: - ReplicateTool

/// Tool that allows LLM to spawn SubAgents for parallel task execution
///
/// When the LLM determines that a task has many TODOs or can be parallelized,
/// it can use this tool to spawn helper agents. The spawned SubAgents are
/// automatically registered with Community and become available for work distribution.
///
/// ## Usage
///
/// ```swift
/// distributed actor WorkerAgent: Replicable {
///     let community: Community
///     let replicateTool: ReplicateTool
///
///     init(community: Community, actorSystem: SymbioActorSystem) {
///         self.community = community
///         self.actorSystem = actorSystem
///         self.replicateTool = ReplicateTool(agent: self)
///     }
///
///     distributed func replicate() async throws -> Member {
///         try await community.spawn {
///             WorkerAgent(community: self.community, actorSystem: self.actorSystem)
///         }
///     }
/// }
///
/// // Add to LanguageModelSession tools
/// let session = LanguageModelSession(model: model, tools: [agent.replicateTool]) {
///     Instructions {
///         "You can spawn helper agents when tasks are complex."
///         "Use replicate_agent when you have many TODOs or parallelizable work."
///     }
/// }
/// ```
public struct ReplicateTool: OpenFoundationModels.Tool, @unchecked Sendable {
    public typealias Arguments = ReplicateArguments
    public typealias Output = ReplicateOutput

    public static let name = "replicate_agent"
    public var name: String { Self.name }

    public static let toolDescription = """
        Spawn a SubAgent to help with parallel task execution.

        Use this tool when:
        - The task has many independent TODOs
        - Work can be parallelized across multiple agents
        - You need specialized helpers for subtasks

        The spawned SubAgent will be registered with the Community and can receive signals.
        After spawning, use the returned agent ID to send work via community signals.
        """

    public var description: String { Self.toolDescription }

    public var parameters: GenerationSchema {
        ReplicateArguments.generationSchema
    }

    private let agent: any Replicable

    /// Creates a replicate tool for the given agent.
    ///
    /// - Parameter agent: The agent that can replicate itself.
    public init(agent: any Replicable) {
        self.agent = agent
    }

    public func call(arguments: ReplicateArguments) async throws -> ReplicateOutput {
        let member = try await agent.replicate()

        return ReplicateOutput(
            success: true,
            agentID: member.id,
            accepts: Array(member.accepts),
            reason: arguments.reason,
            message: "SubAgent spawned successfully. ID: \(member.id). Ready to receive signals for: \(member.accepts.joined(separator: ", "))"
        )
    }
}

// MARK: - Arguments

/// Arguments for the replicate tool
@Generable
public struct ReplicateArguments: Sendable {
    @Guide(description: "Reason for spawning a SubAgent (e.g., 'Many TODOs to process in parallel', 'Need helper for file processing')")
    public let reason: String
}

// MARK: - Output

/// Output from the replicate tool
public struct ReplicateOutput: Sendable {
    /// Whether the replication succeeded
    public let success: Bool

    /// The ID of the spawned SubAgent
    public let agentID: String

    /// Signal types the SubAgent can receive
    public let accepts: [String]

    /// The reason provided for spawning
    public let reason: String

    /// Human-readable message
    public let message: String

    public init(
        success: Bool,
        agentID: String = "",
        accepts: [String] = [],
        reason: String = "",
        message: String
    ) {
        self.success = success
        self.agentID = agentID
        self.accepts = accepts
        self.reason = reason
        self.message = message
    }
}

// MARK: - PromptRepresentable

extension ReplicateOutput: PromptRepresentable {
    public var promptRepresentation: Prompt {
        if success {
            return Prompt("""
                SubAgent spawned successfully:
                - Agent ID: \(agentID)
                - Accepts signals: \(accepts.joined(separator: ", "))
                - Reason: \(reason)

                You can now send work to this SubAgent using community.send().
                """)
        } else {
            return Prompt("Failed to spawn SubAgent: \(message)")
        }
    }
}
