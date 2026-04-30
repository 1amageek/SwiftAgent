//
//  Claim.swift
//  SwiftAgentSymbio
//

import Foundation

public struct Claim: Identifiable, Sendable, Codable, Hashable {
    public let id: String
    public let subjectID: ParticipantID
    public let predicate: String
    public let object: String
    public let issuerID: ParticipantID
    public let issuedAt: Date
    public let confidence: Double?

    public init(
        id: String = UUID().uuidString,
        subjectID: ParticipantID,
        predicate: String,
        object: String,
        issuerID: ParticipantID,
        issuedAt: Date = Date(),
        confidence: Double? = nil
    ) {
        self.id = id
        self.subjectID = subjectID
        self.predicate = predicate
        self.object = object
        self.issuerID = issuerID
        self.issuedAt = issuedAt
        self.confidence = confidence
    }
}
