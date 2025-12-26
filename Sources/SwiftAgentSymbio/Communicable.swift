// MARK: - Communicable
// Protocol for agents that can communicate with other agents
// Uses Swift Distributed Actors for transparent local/remote communication

import Foundation
import SwiftAgent
import Distributed
import DiscoveryCore

// MARK: - Communicable Protocol

/// Communicable - A distributed actor that can communicate within a community
///
/// This protocol provides all communication capabilities for agents:
/// - Community membership (community, perceptions)
/// - Signal receiving (receive)
///
/// Usage:
/// ```swift
/// distributed actor MyAgent: Communicable {
///     let community: Community
///
///     init(community: Community, actorSystem: SymbioActorSystem) {
///         self.community = community
///         self.actorSystem = actorSystem
///     }
///
///     nonisolated var perceptions: [any Perception] {
///         [NetworkPerception()]
///     }
///
///     distributed func receive(_ data: Data, perception: String) async throws -> Data? {
///         // Handle signals...
///     }
/// }
/// ```
public protocol Communicable: DistributedActor where ActorSystem == SymbioActorSystem {
    /// The community this agent belongs to
    var community: Community { get }

    /// Available perceptions (ways this agent can receive signals)
    /// This property is nonisolated to allow access without await
    nonisolated var perceptions: [any Perception] { get }

    /// Receive a signal
    /// - Parameters:
    ///   - data: Serialized signal data
    ///   - perception: The perception identifier
    /// - Returns: Optional response data
    distributed func receive(_ data: Data, perception: String) async throws -> Data?
}

// MARK: - Terminatable Protocol

/// Protocol for agents that can be gracefully terminated
///
/// Implement this protocol to perform cleanup before an agent is removed
/// from the community. This is called by `Community.terminate(_:)` before
/// the agent reference is released.
///
/// Usage:
/// ```swift
/// distributed actor MyAgent: CommunityAgent, Terminatable {
///     nonisolated func terminate() async {
///         // Save state, close connections, etc.
///     }
/// }
/// ```
public protocol Terminatable: Actor {
    /// Called before the agent is removed from the community
    /// Use this to clean up resources, save state, close connections, etc.
    nonisolated func terminate() async
}

// MARK: - Replicable Protocol

/// Protocol for agents that can replicate themselves
///
/// Implement this protocol to allow an agent to spawn a copy of itself.
/// This is useful for scaling out work or creating helper agents dynamically.
///
/// The LLM can use `ReplicateTool` to spawn SubAgents when it determines
/// that a task has many TODOs or can be parallelized.
///
/// Usage:
/// ```swift
/// distributed actor WorkerAgent: Communicable, Replicable {
///     let community: Community
///
///     func replicate() async throws -> Member {
///         try await community.spawn {
///             WorkerAgent(community: self.community, actorSystem: self.actorSystem)
///         }
///     }
///
///     // When work is too heavy, spawn a helper
///     func handleHeavyWork() async throws {
///         let helper = try await replicate()
///         try await community.send(halfOfWork, to: helper, perception: "work")
///     }
/// }
/// ```
public protocol Replicable: Actor {
    /// Create a copy of this agent
    /// - Returns: Member representing the newly spawned agent
    func replicate() async throws -> Member
}

// MARK: - Communicable Default Implementation

extension Communicable {
    /// Find members who can receive a specific signal type
    public func whoCanReceive(_ perception: String) async -> [Member] {
        await community.whoCanReceive(perception)
    }

    /// Find members who provide a specific capability
    public func whoProvides(_ capability: String) async -> [Member] {
        await community.whoProvides(capability)
    }

    /// Send a signal to a member
    public func send<S: Sendable & Codable>(
        _ signal: S,
        to member: Member,
        perception: String
    ) async throws -> Data? {
        try await community.send(signal, to: member, perception: perception)
    }

    /// Invoke a capability on a member
    public func invoke(
        _ capability: String,
        on member: Member,
        with arguments: Data
    ) async throws -> Data {
        try await community.invoke(capability, on: member, with: arguments)
    }

    /// Observe community changes
    public var communityChanges: AsyncStream<CommunityChange> {
        get async {
            await community.changes
        }
    }
}

