//
//  PolicyAuthorization.swift
//  SwiftAgentSymbio
//

import Foundation

public struct PolicyRequest: Identifiable, Sendable, Codable, Hashable {
    public let id: String
    public let routePlanID: String
    public let messageID: String
    public let policyIDs: Set<String>
    public let participantIDs: Set<ParticipantID>
    public let evidenceInputs: Set<String>
    public let requestedAt: Date

    public init(
        id: String = UUID().uuidString,
        routePlanID: String,
        messageID: String,
        policyIDs: Set<String>,
        participantIDs: Set<ParticipantID>,
        evidenceInputs: Set<String>,
        requestedAt: Date = Date()
    ) {
        self.id = id
        self.routePlanID = routePlanID
        self.messageID = messageID
        self.policyIDs = policyIDs
        self.participantIDs = participantIDs
        self.evidenceInputs = evidenceInputs
        self.requestedAt = requestedAt
    }
}

public protocol PolicyAuthorizer: Sendable {
    func authorize(_ request: PolicyRequest) async -> PolicyDecision
}
