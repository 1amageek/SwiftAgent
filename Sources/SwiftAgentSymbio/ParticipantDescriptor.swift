//
//  ParticipantDescriptor.swift
//  SwiftAgentSymbio
//

import Foundation

public enum ParticipantKind: String, Sendable, Codable, Hashable {
    case agent
    case robot
    case device
    case human
    case aggregate
    case service
    case unknown
}

public struct ParticipantDescriptor: Identifiable, Sendable, Codable, Hashable {
    public let id: ParticipantID
    public let displayName: String?
    public let kind: ParticipantKind
    public let representations: Set<MessageRepresentation>
    public let capabilityContracts: Set<CapabilityContract>
    public let selfClaims: [Claim]
    public let metadata: [String: String]

    public init(
        id: ParticipantID,
        displayName: String? = nil,
        kind: ParticipantKind = .unknown,
        representations: Set<MessageRepresentation> = [],
        capabilityContracts: Set<CapabilityContract> = [],
        selfClaims: [Claim] = [],
        metadata: [String: String] = [:]
    ) {
        self.id = id
        self.displayName = displayName
        self.kind = kind
        self.representations = representations
        self.capabilityContracts = capabilityContracts
        self.selfClaims = selfClaims
        self.metadata = metadata
    }
}
