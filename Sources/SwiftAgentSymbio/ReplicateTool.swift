//
//  ReplicateTool.swift
//  SwiftAgentSymbio
//
//  Created by SwiftAgent.
//

import Foundation
import SwiftAgent

// MARK: - ReplicateTool

/// Tool that allows LLM to spawn SubAgents for parallel task execution
///
/// When the LLM determines that a task has many TODOs or can be parallelized,
/// it can use this tool to spawn helper agents. The spawned SubAgents are
/// automatically registered with the runtime and become available for work distribution.
///
/// ## Usage
///
/// ```swift
/// distributed actor WorkerAgent: Communicable, Replicable {
///     let runtime: SymbioRuntime
///     let replicateTool: ReplicateTool
///
///     init(runtime: SymbioRuntime, actorSystem: SymbioActorSystem) {
///         self.runtime = runtime
///         self.actorSystem = actorSystem
///         self.replicateTool = ReplicateTool(agent: self)
///     }
///
///     func replicate() async throws -> ParticipantView {
///         try await runtime.spawn {
///             WorkerAgent(runtime: self.runtime, actorSystem: self.actorSystem)
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
public struct ReplicateTool: Tool, Sendable {
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

        The spawned SubAgent will be registered with the runtime and can receive signals.
        After spawning, use the returned agent ID to send work through runtime signals.
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
        let participant = try await agent.replicate()

        return ReplicateOutput(
            success: true,
            participantID: participant.id.rawValue,
            affordances: participant.affordances.map(\.contract.id).sorted(),
            reason: arguments.reason,
            message: "SubAgent spawned successfully. ID: \(participant.id.rawValue)."
        )
    }
}

// MARK: - Arguments

/// Arguments for the replicate tool
@Generable
public struct ReplicateArguments: Sendable {
    @Guide(description: "Reason for spawning a SubAgent")
    public let reason: String
}

// MARK: - Output

/// Output from the replicate tool
public struct ReplicateOutput: Sendable {
    /// Whether the replication succeeded
    public let success: Bool

    /// The ID of the spawned SubAgent participant
    public let participantID: String

    /// Affordances advertised by the SubAgent
    public let affordances: [String]

    /// The reason provided for spawning
    public let reason: String

    /// Human-readable message
    public let message: String

    public init(
        success: Bool,
        participantID: String = "",
        affordances: [String] = [],
        reason: String = "",
        message: String
    ) {
        self.success = success
        self.participantID = participantID
        self.affordances = affordances
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
                - Participant ID: \(participantID)
                - Affordances: \(affordances.joined(separator: ", "))
                - Reason: \(reason)

                You can now send work to this SubAgent using runtime.send(..., to: participantID, ...).
                """)
        } else {
            return Prompt("Failed to spawn SubAgent: \(message)")
        }
    }
}
