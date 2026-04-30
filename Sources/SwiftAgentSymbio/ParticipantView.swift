//
//  ParticipantView.swift
//  SwiftAgentSymbio
//

import Foundation

public struct ParticipantView: Identifiable, Sendable, Codable, Hashable {
    public var id: ParticipantID {
        descriptor.id
    }

    public let descriptor: ParticipantDescriptor
    public let availability: Availability
    public let affordances: [Affordance]
    public let claims: [Claim]
    public let evidence: [Evidence]
    public let trustViews: [TrustView]
    public let isBlocked: Bool
    public let constraints: [String]

    public init(
        descriptor: ParticipantDescriptor,
        availability: Availability,
        affordances: [Affordance],
        claims: [Claim],
        evidence: [Evidence],
        trustViews: [TrustView],
        isBlocked: Bool,
        constraints: [String] = []
    ) {
        self.descriptor = descriptor
        self.availability = availability
        self.affordances = affordances
        self.claims = claims
        self.evidence = evidence
        self.trustViews = trustViews
        self.isBlocked = isBlocked
        self.constraints = constraints
    }
}
