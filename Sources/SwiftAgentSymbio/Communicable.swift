//
//  Communicable.swift
//  SwiftAgentSymbio
//
//  Created by SwiftAgent.
//

import Foundation
import SwiftAgent
import Distributed

// MARK: - Communicable Protocol

/// Communicable - A distributed actor that can communicate through a runtime.
///
/// This protocol provides all communication capabilities for agents:
/// - runtime participant view
/// - declared perceptions
/// - Signal receiving (receive)
///
/// Usage:
/// ```swift
/// distributed actor MyAgent: Communicable {
///     let runtime: SymbioRuntime
///
///     init(runtime: SymbioRuntime, actorSystem: SymbioActorSystem) {
///         self.runtime = runtime
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
    /// The runtime this agent belongs to.
    var runtime: SymbioRuntime { get }

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

// MARK: - CapabilityProviding Protocol

/// A distributed actor that exposes remotely invocable capabilities.
///
/// `perceptions` are signal receivers. `providedCapabilities` are request /
/// response actions that can be invoked through the runtime.
public protocol CapabilityProviding: DistributedActor where ActorSystem == SymbioActorSystem {
    /// Capability identifiers this actor provides.
    nonisolated var providedCapabilities: Set<String> { get }

    /// Invoke a capability with serialized arguments.
    /// - Parameters:
    ///   - data: Serialized arguments
    ///   - capability: Capability identifier
    /// - Returns: Serialized result data
    distributed func invokeCapability(_ data: Data, capability: String) async throws -> Data
}

// MARK: - Terminatable Protocol

/// Protocol for agents that can be gracefully terminated
///
/// Implement this protocol to perform cleanup before an agent is removed
/// from the runtime. This is called by `SymbioRuntime.terminate(_:)` before
/// the agent reference is released.
///
/// Usage:
/// ```swift
/// distributed actor MyAgent: Communicable, Terminatable {
///     nonisolated func terminate() async {
///         // Save state, close connections, etc.
///     }
/// }
/// ```
public protocol Terminatable: Actor {
    /// Called before the agent is removed from the runtime.
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
/// Note: This protocol uses `Sendable` constraint for flexibility, allowing
/// both `Actor` and `DistributedActor` types to conform.
///
/// Usage:
/// ```swift
/// distributed actor WorkerAgent: Communicable, Replicable {
///     let runtime: SymbioRuntime
///
///     func replicate() async throws -> ParticipantView {
///         try await runtime.spawn {
///             WorkerAgent(runtime: self.runtime, actorSystem: self.actorSystem)
///         }
///     }
///
///     // When work is too heavy, spawn a helper
///     func handleHeavyWork() async throws {
///         let helper = try await replicate()
///         try await runtime.send(halfOfWork, to: helper.id, perception: "work")
///     }
/// }
/// ```
public protocol Replicable: Sendable {
    /// Create a copy of this agent
    /// - Returns: Participant view representing the newly spawned agent
    func replicate() async throws -> ParticipantView
}

// MARK: - Communicable Default Implementation

extension Communicable {
    /// Read the currently available participants in the local subjective runtime view.
    public var availableParticipants: [ParticipantView] {
        get async {
            await runtime.availableParticipants
        }
    }

    /// Send a signal to a participant.
    public func send<S: Sendable & Codable>(
        _ signal: S,
        to participantID: ParticipantID,
        perception: String
    ) async throws -> Data? {
        try await runtime.send(signal, to: participantID, perception: perception)
    }

    /// Invoke a capability on a participant.
    public func invoke(
        _ capability: String,
        on participantID: ParticipantID,
        with arguments: Data
    ) async throws -> Data {
        try await runtime.invoke(capability, on: participantID, with: arguments)
    }

    /// Observe runtime view changes.
    public var runtimeChanges: AsyncStream<SymbioRuntimeChange> {
        get async {
            await runtime.changes
        }
    }
}
