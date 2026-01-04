//
//  PeerConnector.swift
//  SwiftAgentSymbio
//
//  Created by SwiftAgent.
//

import Foundation
import SwiftAgent
import Discovery
import DiscoveryCore

// MARK: - CapabilityID Namespace for Agent Layer

/// Namespace for agent-layer capability IDs
public enum AgentCapabilityNamespace {
    /// Namespace for perception capabilities (what an agent can receive)
    public static let perception = "agent.perception"

    /// Namespace for action capabilities (what an agent can do/provide)
    public static let action = "agent.action"
}

// MARK: - Perception to CapabilityID Conversion

extension Perception {
    /// Convert this perception to a CapabilityID for discovery
    /// Uses the perception namespace with the identifier as the name
    public var capabilityID: CapabilityID {
        // Format: agent.perception.{identifier}
        // swiftlint:disable:next force_try
        try! CapabilityID(parsing: "\(AgentCapabilityNamespace.perception).\(identifier)")
    }
}

extension Array where Element == any Perception {
    /// Convert perceptions to CapabilityIDs for accepts
    public var capabilityIDs: [CapabilityID] {
        map { $0.capabilityID }
    }
}

extension Array where Element == String {
    /// Convert perception identifiers to CapabilityIDs
    public var toCapabilityIDs: [CapabilityID] {
        compactMap { identifier in
            try? CapabilityID(parsing: "\(AgentCapabilityNamespace.perception).\(identifier)")
        }
    }
}

// MARK: - PeerConnector

/// Connects the Agent layer to the peer network
///
/// PeerConnector provides:
/// - Conversion between Perception/Presence and CapabilityID/ResolvedPeer
/// - Unified discovery interface using swift-discovery's TransportCoordinator
/// - Message routing between agents
///
/// Layer mapping:
/// - Agent's perceptions → accepts (what the agent can receive)
/// - Agent's capabilities → provides (what the agent can do)
public actor PeerConnector {

    // MARK: - Properties

    /// The transport coordinator from swift-discovery
    private let coordinator: TransportCoordinator

    /// Local peer representation
    private let localPeer: LocalPeer

    /// Invocation handler for incoming requests
    private var invocationHandler: IncomingInvocationHandler?

    // MARK: - Initialization

    /// Create a new PeerConnector
    /// - Parameters:
    ///   - name: Local peer name (agent identifier)
    ///   - perceptions: Perceptions this agent can receive (becomes accepts)
    ///   - capabilities: Capabilities this agent provides (becomes provides)
    ///   - displayName: Human-readable display name
    ///   - metadata: Additional metadata
    public init(
        name: String,
        perceptions: [any Perception] = [],
        capabilities: [CapabilityID] = [],
        displayName: String? = nil,
        metadata: [String: String] = [:]
    ) {
        // Convert perceptions to accepts CapabilitySet
        let acceptsCapabilities = perceptions.map { perception in
            Capability(
                id: perception.capabilityID,
                description: "Perception: \(perception.identifier)"
            )
        }
        let acceptsSet = CapabilitySet(capabilities: acceptsCapabilities)

        // Convert capabilities to provides CapabilitySet
        let providesCapabilities = capabilities.map { capID in
            Capability(id: capID, description: capID.fullString)
        }
        let providesSet = CapabilitySet(capabilities: providesCapabilities)

        self.localPeer = LocalPeer(
            name: name,
            provides: providesSet,
            accepts: acceptsSet,
            displayName: displayName,
            metadata: metadata
        )

        self.coordinator = TransportCoordinator(localPeer: localPeer)
    }

    /// Create a new PeerConnector from perception identifiers
    /// - Parameters:
    ///   - name: Local peer name (agent identifier)
    ///   - perceptionIdentifiers: Perception identifier strings (becomes accepts)
    ///   - provideIdentifiers: Capability identifier strings (becomes provides)
    ///   - displayName: Human-readable display name
    ///   - metadata: Additional metadata
    public init(
        name: String,
        perceptionIdentifiers: [String] = [],
        provideIdentifiers: [String] = [],
        displayName: String? = nil,
        metadata: [String: String] = [:]
    ) {
        // Convert perception identifiers to accepts CapabilitySet
        let acceptsCapabilities = perceptionIdentifiers.compactMap { identifier -> Capability? in
            guard let capID = try? CapabilityID(parsing: "\(AgentCapabilityNamespace.perception).\(identifier)") else {
                return nil
            }
            return Capability(id: capID, description: "Perception: \(identifier)")
        }
        let acceptsSet = CapabilitySet(capabilities: acceptsCapabilities)

        // Convert provide identifiers to provides CapabilitySet
        let providesCapabilities = provideIdentifiers.compactMap { identifier -> Capability? in
            guard let capID = try? CapabilityID(parsing: identifier) else {
                return nil
            }
            return Capability(id: capID, description: identifier)
        }
        let providesSet = CapabilitySet(capabilities: providesCapabilities)

        self.localPeer = LocalPeer(
            name: name,
            provides: providesSet,
            accepts: acceptsSet,
            displayName: displayName,
            metadata: metadata
        )

        self.coordinator = TransportCoordinator(localPeer: localPeer)
    }

    // MARK: - Transport Management

    /// Register a transport with the coordinator
    public func register<T: DiscoveryCore.Transport>(_ transport: T) async {
        await coordinator.register(transport)
    }

    /// Unregister a transport
    public func unregister(_ transportID: String) async {
        await coordinator.unregister(transportID)
    }

    /// Start all registered transports
    public func start() async throws {
        try await coordinator.startAll()
    }

    /// Stop all registered transports
    public func stop() async throws {
        try await coordinator.stopAll()
    }

    // MARK: - Invocation Handler

    /// Set the handler for incoming invocation requests
    public func setInvocationHandler(_ handler: @escaping IncomingInvocationHandler) async {
        self.invocationHandler = handler
        await coordinator.setIncomingInvocationHandler(handler)
    }

    /// Remove the invocation handler
    public func removeInvocationHandler() async {
        self.invocationHandler = nil
        await coordinator.removeIncomingInvocationHandler()
    }

    // MARK: - Discovery

    /// Discover agents that can receive a specific perception
    /// - Parameters:
    ///   - perceptionIdentifier: The perception identifier to search for
    ///   - timeout: Maximum time to wait for responses
    /// - Returns: Stream of discovered peers that accept this perception
    public func discoverReceivers(
        for perceptionIdentifier: String,
        timeout: Duration = .seconds(5)
    ) async -> AsyncThrowingStream<DiscoveredPeer, Error> {
        guard let capID = try? CapabilityID(parsing: "\(AgentCapabilityNamespace.perception).\(perceptionIdentifier)") else {
            return AsyncThrowingStream { $0.finish() }
        }
        return await coordinator.discover(accepts: capID, timeout: timeout)
    }

    /// Discover agents that provide a specific capability
    /// - Parameters:
    ///   - capabilityID: The capability to search for
    ///   - timeout: Maximum time to wait for responses
    /// - Returns: Stream of discovered peers that provide this capability
    public func discoverProviders(
        for capabilityID: CapabilityID,
        timeout: Duration = .seconds(5)
    ) async -> AsyncThrowingStream<DiscoveredPeer, Error> {
        await coordinator.discover(provides: capabilityID, timeout: timeout)
    }

    /// Discover all agents
    /// - Parameter timeout: Maximum time to wait for responses
    /// - Returns: Stream of all discovered peers
    public func discoverAll(
        timeout: Duration = .seconds(5)
    ) -> AsyncThrowingStream<ResolvedPeer, Error> {
        AsyncThrowingStream { continuation in
            Task {
                var seen: Set<PeerID> = []

                for transport in await self.coordinator.allTransports {
                    for try await peer in transport.discoverAll(timeout: timeout) {
                        if !seen.contains(peer.peerID) {
                            seen.insert(peer.peerID)
                            if let resolved = try? await transport.resolve(peer.peerID) {
                                continuation.yield(resolved)
                            }
                        }
                    }
                }

                continuation.finish()
            }
        }
    }

    // MARK: - Resolution

    /// Resolve a peer by ID
    /// - Parameter peerID: The peer to resolve
    /// - Returns: Resolved peer or nil if not found
    public func resolve(_ peerID: PeerID) async throws -> ResolvedPeer? {
        try await coordinator.resolve(peerID)
    }

    /// Resolve a peer by agent ID string
    /// - Parameter agentID: The agent ID string
    /// - Returns: Resolved peer or nil if not found
    public func resolve(agentID: String) async throws -> ResolvedPeer? {
        let peerID = PeerID(agentID)
        return try await coordinator.resolve(peerID)
    }

    // MARK: - Invocation

    /// Invoke a capability on a remote peer
    /// - Parameters:
    ///   - capability: The capability to invoke
    ///   - peerID: Target peer ID
    ///   - arguments: Invocation arguments
    ///   - timeout: Maximum time to wait for response
    /// - Returns: Invocation result
    public func invoke(
        _ capability: CapabilityID,
        on peerID: PeerID,
        arguments: Data,
        timeout: Duration = .seconds(30)
    ) async throws -> InvocationResult {
        try await coordinator.invoke(capability, on: peerID, arguments: arguments, timeout: timeout)
    }

    // MARK: - Presence Conversion

    /// Convert a Presence to a ResolvedPeer-compatible format
    /// - Parameter presence: The presence to convert
    /// - Returns: Equivalent accepts capability IDs
    public static func presenceToAccepts<ID: Hashable & Sendable & Codable>(
        _ presence: Presence<ID>
    ) -> [CapabilityID] {
        presence.perceptions.compactMap { identifier in
            try? CapabilityID(parsing: "\(AgentCapabilityNamespace.perception).\(identifier)")
        }
    }

    /// Convert a ResolvedPeer to Presence-compatible format
    /// - Parameter peer: The resolved peer
    /// - Returns: Perception identifiers extracted from accepts
    public static func peerToPerceptionIdentifiers(_ peer: ResolvedPeer) -> [String] {
        peer.accepts.compactMap { capID -> String? in
            let fullString = capID.fullString
            let prefix = "\(AgentCapabilityNamespace.perception)."
            guard fullString.hasPrefix(prefix) else { return nil }
            return String(fullString.dropFirst(prefix.count))
        }
    }

    /// Create a Presence from a ResolvedPeer
    /// - Parameter peer: The resolved peer
    /// - Returns: A Presence with the peer's accepts converted to perceptions
    public static func peerToPresence(_ peer: ResolvedPeer) -> Presence<String> {
        let perceptions = peerToPerceptionIdentifiers(peer)
        return Presence(
            id: peer.peerID.name,
            perceptions: perceptions,
            timestamp: peer.resolvedAt,
            ttl: peer.ttl.timeInterval
        )
    }
}

// MARK: - Duration Extension

extension Duration {
    /// Convert Duration to TimeInterval
    var timeInterval: TimeInterval {
        let (seconds, attoseconds) = self.components
        return TimeInterval(seconds) + TimeInterval(attoseconds) / 1e18
    }
}

// MARK: - Backward Compatibility

/// Backward compatibility alias
@available(*, deprecated, renamed: "PeerConnector")
public typealias DiscoveryBridge = PeerConnector
