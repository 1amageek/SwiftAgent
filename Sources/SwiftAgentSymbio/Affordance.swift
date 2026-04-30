//
//  Affordance.swift
//  SwiftAgentSymbio
//

import Foundation

public enum AffordanceState: String, Sendable, Codable, Hashable {
    case available
    case degraded
    case unavailable
    case unknown
}

public struct Affordance: Identifiable, Sendable, Codable, Hashable {
    public let id: String
    public let ownerID: ParticipantID
    public let contract: CapabilityContract
    public let state: AffordanceState
    public let deliveryOptions: [DeliveryOption]
    public let evidenceIDs: Set<String>
    public let metadata: [String: String]

    public init(
        id: String = UUID().uuidString,
        ownerID: ParticipantID,
        contract: CapabilityContract,
        state: AffordanceState = .available,
        deliveryOptions: [DeliveryOption] = [],
        evidenceIDs: Set<String> = [],
        metadata: [String: String] = [:]
    ) {
        self.id = id
        self.ownerID = ownerID
        self.contract = contract
        self.state = state
        self.deliveryOptions = deliveryOptions
        self.evidenceIDs = evidenceIDs
        self.metadata = metadata
    }
}
