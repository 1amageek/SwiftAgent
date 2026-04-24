//
//  RouteCandidate.swift
//  SwiftAgentSymbio
//

import Foundation

public struct RouteCandidate: Identifiable, Sendable, Codable, Hashable {
    public var id: String { member.id }

    public let member: Member
    public let score: Double
    public let reasons: [String]
    public let risks: [String]

    public init(
        member: Member,
        score: Double,
        reasons: [String],
        risks: [String] = []
    ) {
        self.member = member
        self.score = score
        self.reasons = reasons
        self.risks = risks
    }
}
