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
import ActorRuntime

// MARK: - SymbioActorSystem

/// A distributed actor system for local agent invocation routing.
public final class SymbioActorSystem: DistributedActorSystem, Sendable {

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

    /// Default timeout for remote calls.
    private let defaultTimeoutStorage: Mutex<Duration> = Mutex(.seconds(30))

    public var defaultTimeout: Duration {
        get {
            defaultTimeoutStorage.withLock { $0 }
        }
        set {
            defaultTimeoutStorage.withLock { $0 = newValue }
        }
    }

    // MARK: - Initialization

    /// Create a new SymbioActorSystem
    /// - Parameter localActorID: Optional local actor ID (generates new one if nil)
    public init(localActorID: Address? = nil) {
        self.localActorID = localActorID ?? Address()
        self.actorRegistry = ActorRuntime.ActorRegistry()
    }

    // MARK: - Incoming Invocation

    /// Route an incoming transport invocation to a local communicable actor.
    public func handleIncomingInvocation(
        _ envelope: SymbioInvocationEnvelope,
        from senderID: String
    ) async -> SymbioInvocationReply {
        let capabilityString = envelope.capability

        guard let actorID = actorID(for: capabilityString) else {
            return SymbioInvocationReply.failure(
                invocationID: envelope.invocationID,
                code: SymbioErrorCode.notFound.rawValue,
                message: "No actor registered for capability: \(capabilityString)"
            )
        }

        guard let actor = actorRegistry.find(id: actorID.hexString) else {
            return SymbioInvocationReply.failure(
                invocationID: envelope.invocationID,
                code: SymbioErrorCode.notFound.rawValue,
                message: "Actor not found: \(actorID)"
            )
        }

        let prefix = "\(AgentCapabilityNamespace.perception)."
        if capabilityString.hasPrefix(prefix) {
            guard let signalReceiver = actor as? any Communicable else {
                return SymbioInvocationReply.failure(
                    invocationID: envelope.invocationID,
                    code: SymbioErrorCode.notFound.rawValue,
                    message: "Actor does not implement Communicable"
                )
            }
            let perception = String(capabilityString.dropFirst(prefix.count))

            do {
                let result = try await signalReceiver.receive(envelope.arguments, perception: perception)
                return SymbioInvocationReply.success(invocationID: envelope.invocationID, result: result)
            } catch {
                return SymbioInvocationReply.failure(
                    invocationID: envelope.invocationID,
                    code: SymbioErrorCode.invocationFailed.rawValue,
                    message: error.localizedDescription
                )
            }
        }

        guard let capabilityProvider = actor as? any CapabilityProviding else {
            return SymbioInvocationReply.failure(
                invocationID: envelope.invocationID,
                code: SymbioErrorCode.notFound.rawValue,
                message: "Actor does not provide capability: \(capabilityString)"
            )
        }

        do {
            let result = try await capabilityProvider.invokeCapability(
                envelope.arguments,
                capability: capabilityString
            )
            return SymbioInvocationReply.success(invocationID: envelope.invocationID, result: result)
        } catch {
            return SymbioInvocationReply.failure(
                invocationID: envelope.invocationID,
                code: SymbioErrorCode.invocationFailed.rawValue,
                message: error.localizedDescription
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

        // Remote actors are reached through SymbioRuntime transport invocation.
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

        // Remote actors are reached through SymbioRuntime transport invocation.
        throw SymbioError.actorNotLocal(actor.id)
    }

    // MARK: - Private: Local Call Implementation

    /// Thread-safe holder for capturing invocation responses across async boundaries
    private final class ResponseHolder: Sendable {
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
