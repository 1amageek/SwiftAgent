//
//  CommunityPeerView.swift
//  SwiftAgentSymbio
//

import Foundation

public struct CommunityPeerView: Identifiable, Sendable, Codable, Hashable {
    public var id: String { member.id }

    public let member: Member
    public let isLocal: Bool
    public let isBlocked: Bool
    public let trustScore: Double
    public let claims: [SemanticClaim]
    public let observations: [PeerObservation]

    public init(
        member: Member,
        isLocal: Bool,
        isBlocked: Bool,
        trustScore: Double,
        claims: [SemanticClaim],
        observations: [PeerObservation]
    ) {
        self.member = member
        self.isLocal = isLocal
        self.isBlocked = isBlocked
        self.trustScore = trustScore
        self.claims = claims
        self.observations = observations
    }
}
