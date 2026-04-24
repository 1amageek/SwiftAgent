//
//  PeerRecord.swift
//  SwiftAgentSymbio
//

import Foundation

struct PeerRecord: Sendable, Codable {
    var member: Member
    var location: PeerLocation
    var claims: [SemanticClaim]
    var observations: [PeerObservation]
    var trustScore: Double
    var isBlocked: Bool

    init(
        member: Member,
        location: PeerLocation,
        claims: [SemanticClaim] = [],
        observations: [PeerObservation] = [],
        trustScore: Double = 0,
        isBlocked: Bool = false
    ) {
        self.member = member
        self.location = location
        self.claims = claims
        self.observations = observations
        self.trustScore = trustScore
        self.isBlocked = isBlocked
    }

    mutating func observe(_ kind: PeerObservationKind, message: String? = nil) {
        observations.append(PeerObservation(
            peerID: member.id,
            kind: kind,
            message: message
        ))
    }
}
