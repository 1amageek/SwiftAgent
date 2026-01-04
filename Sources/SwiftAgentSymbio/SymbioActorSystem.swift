//
//  SymbioActorSystem.swift
//  SwiftAgentSymbio
//
//  Created by SwiftAgent.
//

import Foundation
import Distributed
import Synchronization
import SwiftAgent
import DiscoveryCore
import ActorRuntime

// MARK: - SymbioActorSystem

/// A distributed actor system for agent communication
/// Uses PeerConnector for discovery and remote invocation
public final class SymbioActorSystem: DistributedActorSystem, @unchecked Sendable {

    // MARK: - Type Aliases

    public typealias ActorID = Address
    public typealias InvocationEncoder = SymbioInvocationEncoder
    public typealias InvocationDecoder = SymbioInvocationDecoder
    public typealias SerializationRequirement = Codable
    public typealias ResultHandler = SymbioResultHandler

    // MARK: - Properties

    /// Local actor identity
    public let localActorID: Address

    /// Local actor registry (from swift-actor-runtime)
    private let actorRegistry: ActorRuntime.ActorRegistry

    /// Whether the system is started
    private let isStarted: Mutex<Bool> = Mutex(false)

    /// Method to actor ID mapping (for incoming invocations)
    private let methodActors: Mutex<[String: Address]> = Mutex([:])

    /// Default timeout for remote calls
    public var defaultTimeout: Duration = .seconds(30)

    /// Peer connector for swift-discovery integration (optional)
    private var peerConnector: PeerConnector?

    // MARK: - Initialization

    /// Create a new SymbioActorSystem
    /// - Parameter localActorID: Optional local actor ID (generates new one if nil)
    public init(localActorID: Address? = nil) {
        self.localActorID = localActorID ?? Address()
        self.actorRegistry = ActorRuntime.ActorRegistry()
    }

    // MARK: - Peer Connector Integration

    /// Set the peer connector for swift-discovery integration
    /// - Parameter connector: The peer connector to use
    public func setPeerConnector(_ connector: PeerConnector) async {
        self.peerConnector = connector

        // Set up invocation handler to route to local actors
        await connector.setInvocationHandler { [weak self] payload, senderID in
            guard let self = self else {
                return InvokeResponsePayload(
                    invocationID: payload.invocationID,
                    success: false,
                    errorCode: DiscoveryErrorCode.resourceUnavailable.rawValue,
                    errorMessage: "Actor system not available"
                )
            }

            return await self.handleDiscoveryInvocation(payload, from: senderID)
        }
    }

    /// Get the peer connector
    public func getPeerConnector() -> PeerConnector? {
        peerConnector
    }

    /// Handle invocation from discovery bridge
    private func handleDiscoveryInvocation(
        _ payload: InvokePayload,
        from senderID: PeerID
    ) async -> InvokeResponsePayload {
        // Find the actor that handles this capability
        let capabilityString = payload.capability.fullString

        guard let actorID = actorID(for: capabilityString) else {
            return InvokeResponsePayload(
                invocationID: payload.invocationID,
                success: false,
                errorCode: DiscoveryErrorCode.capabilityNotFound.rawValue,
                errorMessage: "No actor registered for capability: \(capabilityString)"
            )
        }

        // Find the local actor
        guard let actor = actorRegistry.find(id: actorID.hexString) else {
            return InvokeResponsePayload(
                invocationID: payload.invocationID,
                success: false,
                errorCode: DiscoveryErrorCode.resourceUnavailable.rawValue,
                errorMessage: "Actor not found: \(actorID)"
            )
        }

        // Try to cast to Communicable and call receive() directly
        guard let signalReceiver = actor as? any Communicable else {
            return InvokeResponsePayload(
                invocationID: payload.invocationID,
                success: false,
                errorCode: DiscoveryErrorCode.capabilityNotFound.rawValue,
                errorMessage: "Actor does not implement Communicable"
            )
        }

        // Extract perception identifier from capability string
        // Format: "agent.perception.{identifier}"
        let prefix = "\(AgentCapabilityNamespace.perception)."
        guard capabilityString.hasPrefix(prefix) else {
            return InvokeResponsePayload(
                invocationID: payload.invocationID,
                success: false,
                errorCode: DiscoveryErrorCode.invocationFailed.rawValue,
                errorMessage: "Invalid capability format: \(capabilityString)"
            )
        }
        let perception = String(capabilityString.dropFirst(prefix.count))

        // Call receive() directly
        do {
            let result = try await signalReceiver.receive(payload.arguments, perception: perception)

            return InvokeResponsePayload(
                invocationID: payload.invocationID,
                success: true,
                result: result
            )
        } catch {
            return InvokeResponsePayload(
                invocationID: payload.invocationID,
                success: false,
                errorCode: DiscoveryErrorCode.invocationFailed.rawValue,
                errorMessage: error.localizedDescription
            )
        }
    }

    // MARK: - Lifecycle

    /// Start the actor system
    public func start() async throws {
        try isStarted.withLock { started in
            guard !started else {
                throw SymbioError.alreadyStarted
            }
            started = true
        }
    }

    /// Stop the actor system
    public func stop() async throws {
        try isStarted.withLock { started in
            guard started else {
                throw SymbioError.notStarted
            }
            started = false
        }

        actorRegistry.clear()
    }

    /// Check if the system is running
    public var isRunning: Bool {
        isStarted.withLock { $0 }
    }

    // MARK: - DistributedActorSystem Requirements

    public func resolve<Act>(id: ActorID, as actorType: Act.Type) throws -> Act?
    where Act: DistributedActor, Act.ID == ActorID {
        // Check registry for local actors
        // Following DNS principle: the system resolves, not the ID
        guard let actor = actorRegistry.find(id: id.hexString) else {
            // Not in local registry - may be remote
            return nil
        }
        return actor as? Act
    }

    public func assignID<Act>(_ actorType: Act.Type) -> ActorID
    where Act: DistributedActor, Act.ID == ActorID {
        // Create a new local actor ID
        return Address()
    }

    public func actorReady<Act>(_ actor: Act)
    where Act: DistributedActor, Act.ID == ActorID {
        actorRegistry.register(actor, id: actor.id.hexString)
    }

    public func resignID(_ id: ActorID) {
        actorRegistry.unregister(id: id.hexString)
    }

    public func makeInvocationEncoder() -> InvocationEncoder {
        SymbioInvocationEncoder()
    }

    // MARK: - Remote Calls

    public func remoteCall<Act, Err, Res>(
        on actor: Act,
        target: RemoteCallTarget,
        invocation: inout InvocationEncoder,
        throwing: Err.Type,
        returning: Res.Type
    ) async throws -> Res
    where Act: DistributedActor,
          Act.ID == ActorID,
          Err: Error,
          Res: SerializationRequirement {

        // Check registry to determine if actor is local
        // Following DNS principle: the system resolves, not the ID
        if let localActor = actorRegistry.find(id: actor.id.hexString) {
            // Execute locally using executeDistributedTarget
            return try await executeLocalCall(
                on: localActor,
                target: target,
                invocation: &invocation,
                returning: Res.self
            )
        }

        // Remote actors not directly supported - use Community.send() instead
        throw SymbioError.actorNotLocal(actor.id)
    }

    public func remoteCallVoid<Act, Err>(
        on actor: Act,
        target: RemoteCallTarget,
        invocation: inout InvocationEncoder,
        throwing: Err.Type
    ) async throws
    where Act: DistributedActor,
          Act.ID == ActorID,
          Err: Error {

        // Check registry to determine if actor is local
        // Following DNS principle: the system resolves, not the ID
        if let localActor = actorRegistry.find(id: actor.id.hexString) {
            // Execute locally
            try await executeLocalCallVoid(
                on: localActor,
                target: target,
                invocation: &invocation
            )
            return
        }

        // Remote actors not directly supported - use Community.send() instead
        throw SymbioError.actorNotLocal(actor.id)
    }

    // MARK: - Private: Local Call Implementation

    /// Thread-safe holder for capturing invocation responses across async boundaries
    private final class ResponseHolder: @unchecked Sendable {
        private let mutex = Mutex<InvocationResponse?>(nil)

        func setResponse(_ response: InvocationResponse) {
            mutex.withLock { $0 = response }
        }

        func getResponse() -> InvocationResponse? {
            mutex.withLock { $0 }
        }

        func getResult<T: Codable>(as type: T.Type) throws -> T {
            guard let response = mutex.withLock({ $0 }) else {
                throw SymbioError.deserializationFailed("No response captured")
            }
            return try SymbioResultHandler.decodeResult(from: response, as: type)
        }

        func checkVoidResult() throws {
            guard let response = mutex.withLock({ $0 }) else {
                throw SymbioError.deserializationFailed("No response captured")
            }
            try SymbioResultHandler.checkVoidResult(from: response)
        }
    }

    private func executeLocalCall<Res: Codable>(
        on actor: any DistributedActor,
        target: RemoteCallTarget,
        invocation: inout InvocationEncoder,
        returning: Res.Type
    ) async throws -> Res {
        invocation.recordTarget(target)
        try invocation.doneRecording()

        let argumentsData = try invocation.makeArgumentsData()
        var decoder = try SymbioInvocationDecoder(argumentsData: argumentsData)

        // Use a non-generic class to safely capture result across async boundary
        let responseHolder = ResponseHolder()

        let handler = SymbioResultHandler(invocationID: UUID().uuidString) { response in
            responseHolder.setResponse(response)
        }

        try await executeDistributedTarget(
            on: actor,
            target: target,
            invocationDecoder: &decoder,
            handler: handler
        )

        return try responseHolder.getResult(as: Res.self)
    }

    private func executeLocalCallVoid(
        on actor: any DistributedActor,
        target: RemoteCallTarget,
        invocation: inout InvocationEncoder
    ) async throws {
        invocation.recordTarget(target)
        try invocation.doneRecording()

        let argumentsData = try invocation.makeArgumentsData()
        var decoder = try SymbioInvocationDecoder(argumentsData: argumentsData)

        // Use a non-generic class to safely capture result across async boundary
        let responseHolder = ResponseHolder()

        let handler = SymbioResultHandler(invocationID: UUID().uuidString) { response in
            responseHolder.setResponse(response)
        }

        try await executeDistributedTarget(
            on: actor,
            target: target,
            invocationDecoder: &decoder,
            handler: handler
        )

        try responseHolder.checkVoidResult()
    }

    // MARK: - Method Registration

    /// Register a method for an actor (for incoming invocations)
    /// - Parameters:
    ///   - method: The method identifier
    ///   - actorID: The actor that handles this method
    public func registerMethod(_ method: String, for actorID: Address) {
        methodActors.withLock { $0[method] = actorID }
    }

    /// Unregister a method
    /// - Parameter method: The method identifier to unregister
    public func unregisterMethod(_ method: String) {
        _ = methodActors.withLock { $0.removeValue(forKey: method) }
    }

    /// Get the actor ID for a method
    /// - Parameter method: The method identifier
    /// - Returns: The actor ID, or nil if not registered
    public func actorID(for method: String) -> Address? {
        methodActors.withLock { $0[method] }
    }
}

// MARK: - Peer Connector Extension

extension SymbioActorSystem {

    /// Discover agents that can receive a specific perception using PeerConnector
    /// - Parameters:
    ///   - perceptionIdentifier: The perception identifier to search for
    ///   - timeout: Maximum time to wait for responses
    /// - Returns: Stream of discovered peers that accept this perception
    public func discoverReceivers(
        for perceptionIdentifier: String,
        timeout: Duration = .seconds(5)
    ) async -> AsyncThrowingStream<DiscoveredPeer, Error> {
        guard let connector = peerConnector else {
            return AsyncThrowingStream { continuation in
                continuation.finish(throwing: SymbioError.noTransportAvailable)
            }
        }

        return await connector.discoverReceivers(for: perceptionIdentifier, timeout: timeout)
    }

    /// Discover agents that provide a specific capability using PeerConnector
    /// - Parameters:
    ///   - capabilityID: The capability to search for
    ///   - timeout: Maximum time to wait for responses
    /// - Returns: Stream of discovered peers that provide this capability
    public func discoverProviders(
        for capabilityID: CapabilityID,
        timeout: Duration = .seconds(5)
    ) async -> AsyncThrowingStream<DiscoveredPeer, Error> {
        guard let connector = peerConnector else {
            return AsyncThrowingStream { continuation in
                continuation.finish(throwing: SymbioError.noTransportAvailable)
            }
        }

        return await connector.discoverProviders(for: capabilityID, timeout: timeout)
    }

    /// Resolve a peer by ID using PeerConnector
    /// - Parameter peerID: The peer to resolve
    /// - Returns: Resolved peer or nil if not found
    public func resolvePeer(_ peerID: PeerID) async throws -> ResolvedPeer? {
        guard let connector = peerConnector else {
            throw SymbioError.noTransportAvailable
        }

        return try await connector.resolve(peerID)
    }

    /// Invoke a capability on a remote peer using PeerConnector
    /// - Parameters:
    ///   - capability: The capability to invoke
    ///   - peerID: Target peer ID
    ///   - arguments: Invocation arguments
    ///   - timeout: Maximum time to wait for response
    /// - Returns: Invocation result
    public func invokeCapability(
        _ capability: CapabilityID,
        on peerID: PeerID,
        arguments: Data,
        timeout: Duration = .seconds(30)
    ) async throws -> DiscoveryCore.InvocationResult {
        guard let connector = peerConnector else {
            throw SymbioError.noTransportAvailable
        }

        return try await connector.invoke(capability, on: peerID, arguments: arguments, timeout: timeout)
    }
}
