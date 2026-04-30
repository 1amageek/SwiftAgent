//
//  SymbioTransport.swift
//  SwiftAgentSymbio
//

import Foundation
import SwiftAgent

// MARK: - Agent Capability Namespace

public enum AgentCapabilityNamespace {
    public static let perception = "agent.perception"
    public static let action = "agent.action"
}

extension Perception {
    public var capabilityIdentifier: String {
        "\(AgentCapabilityNamespace.perception).\(identifier)"
    }
}

public enum SymbioTransportEvent: Sendable {
    case peerDiscovered(ParticipantDescriptor)
    case peerLost(ParticipantID)
    case peerConnected(ParticipantID)
    case peerDisconnected(ParticipantID)
    case error(any Error)
}

// MARK: - Invocation Protocol

public struct SymbioInvocationEnvelope: Sendable, Codable, Hashable {
    public let invocationID: String
    public let capability: String
    public let arguments: Data

    public init(
        invocationID: String = UUID().uuidString,
        capability: String,
        arguments: Data
    ) {
        self.invocationID = invocationID
        self.capability = capability
        self.arguments = arguments
    }
}

public struct SymbioInvocationFailure: Sendable, Codable, Hashable {
    public let code: Int
    public let message: String

    public init(code: Int, message: String) {
        self.code = code
        self.message = message
    }
}

public struct SymbioInvocationReply: Sendable, Codable, Hashable {
    public let invocationID: String
    public let success: Bool
    public let result: Data?
    public let failure: SymbioInvocationFailure?

    public init(
        invocationID: String,
        success: Bool,
        result: Data? = nil,
        failure: SymbioInvocationFailure? = nil
    ) {
        self.invocationID = invocationID
        self.success = success
        self.result = result
        self.failure = failure
    }

    public static func success(invocationID: String, result: Data?) -> SymbioInvocationReply {
        SymbioInvocationReply(invocationID: invocationID, success: true, result: result)
    }

    public static func failure(
        invocationID: String,
        code: Int,
        message: String
    ) -> SymbioInvocationReply {
        SymbioInvocationReply(
            invocationID: invocationID,
            success: false,
            failure: SymbioInvocationFailure(code: code, message: message)
        )
    }
}

public typealias SymbioIncomingInvocationHandler = @Sendable (
    _ envelope: SymbioInvocationEnvelope,
    _ senderID: ParticipantID
) async -> SymbioInvocationReply

// MARK: - Transport Boundary

public protocol SymbioTransport: Sendable {
    var events: AsyncStream<SymbioTransportEvent> { get }

    func start() async throws
    func shutdown() async throws
    func setInvocationHandler(_ handler: @escaping SymbioIncomingInvocationHandler) async
    func removeInvocationHandler() async
    func invoke(
        _ envelope: SymbioInvocationEnvelope,
        on peerID: ParticipantID,
        timeout: Duration
    ) async throws -> SymbioInvocationReply
}

public actor LocalOnlySymbioTransport: SymbioTransport {
    public nonisolated var events: AsyncStream<SymbioTransportEvent> {
        AsyncStream { continuation in
            continuation.finish()
        }
    }

    public init() {}

    public func start() async throws {}

    public func shutdown() async throws {}

    public func setInvocationHandler(_ handler: @escaping SymbioIncomingInvocationHandler) async {}

    public func removeInvocationHandler() async {}

    public func invoke(
        _ envelope: SymbioInvocationEnvelope,
        on peerID: ParticipantID,
        timeout: Duration
    ) async throws -> SymbioInvocationReply {
        throw SymbioError.noTransportAvailable
    }
}
