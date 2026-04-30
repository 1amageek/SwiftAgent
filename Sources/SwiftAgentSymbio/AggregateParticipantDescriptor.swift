//
//  AggregateParticipantDescriptor.swift
//  SwiftAgentSymbio
//

import Foundation

public enum AggregateKind: String, Sendable, Codable, Hashable {
    case swarm
    case squad
    case room
    case team
    case fleet
    case custom
}

public struct AggregateMember: Identifiable, Sendable, Codable, Hashable {
    public let id: ParticipantID
    public let weight: Double
    public let role: String?

    public init(id: ParticipantID, weight: Double = 1, role: String? = nil) {
        self.id = id
        self.weight = weight
        self.role = role
    }
}

public enum RollupRule: Sendable, Codable, Hashable {
    case all
    case any
    case quorum(Double)
    case minimumCount(Int)
    case weightedThreshold(Double)
}

public enum DegradationMode: String, Sendable, Codable, Hashable {
    case failClosed
    case bestEffort
    case partialCapability
}

public struct RollupPolicy: Sendable, Codable, Hashable {
    public let availabilityRule: RollupRule
    public let evidenceRule: RollupRule
    public let degradationMode: DegradationMode

    public init(
        availabilityRule: RollupRule,
        evidenceRule: RollupRule,
        degradationMode: DegradationMode = .partialCapability
    ) {
        self.availabilityRule = availabilityRule
        self.evidenceRule = evidenceRule
        self.degradationMode = degradationMode
    }
}

public struct AggregateParticipantDescriptor: Identifiable, Sendable, Codable, Hashable {
    public let id: ParticipantID
    public let displayName: String?
    public let kind: AggregateKind
    public let members: [AggregateMember]
    public let rollupPolicy: RollupPolicy
    public let metadata: [String: String]

    public init(
        id: ParticipantID,
        displayName: String? = nil,
        kind: AggregateKind,
        members: [AggregateMember],
        rollupPolicy: RollupPolicy,
        metadata: [String: String] = [:]
    ) {
        self.id = id
        self.displayName = displayName
        self.kind = kind
        self.members = members
        self.rollupPolicy = rollupPolicy
        self.metadata = metadata
    }
}

public enum AggregateExecutionMode: String, Sendable, Codable, Hashable {
    case broadcast
    case partition
    case leaderDelegated
    case consensus
}

public struct AggregateAffordance: Identifiable, Sendable, Codable, Hashable {
    public let id: String
    public let aggregateID: ParticipantID
    public let contract: CapabilityContract
    public let sourceAffordanceIDs: Set<String>
    public let executionMode: AggregateExecutionMode

    public init(
        id: String = UUID().uuidString,
        aggregateID: ParticipantID,
        contract: CapabilityContract,
        sourceAffordanceIDs: Set<String>,
        executionMode: AggregateExecutionMode
    ) {
        self.id = id
        self.aggregateID = aggregateID
        self.contract = contract
        self.sourceAffordanceIDs = sourceAffordanceIDs
        self.executionMode = executionMode
    }
}
