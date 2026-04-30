//
//  ParticipantRecord.swift
//  SwiftAgentSymbio
//

import Foundation

struct ParticipantRecord: Sendable, Codable {
    var descriptor: ParticipantDescriptor
    var availability: Availability
    var affordances: [Affordance]
    var claims: [Claim]
    var evidence: [Evidence]
    var trustViews: [TrustView]
    var isBlocked: Bool
    var constraints: [String]

    init(
        descriptor: ParticipantDescriptor,
        availability: Availability = .available(),
        affordances: [Affordance] = [],
        claims: [Claim] = [],
        evidence: [Evidence] = [],
        trustViews: [TrustView] = [],
        isBlocked: Bool = false,
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

    var view: ParticipantView {
        ParticipantView(
            descriptor: descriptor,
            availability: availability,
            affordances: affordances,
            claims: claims,
            evidence: evidence,
            trustViews: trustViews,
            isBlocked: isBlocked,
            constraints: constraints
        )
    }
}
