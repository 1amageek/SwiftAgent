//
//  TrustView.swift
//  SwiftAgentSymbio
//

import Foundation

public struct TrustView: Sendable, Codable, Hashable {
    public let issuerID: ParticipantID
    public let subjectID: ParticipantID
    public let evidenceIDs: Set<String>
    public let notes: [String]
    public let updatedAt: Date

    public init(
        issuerID: ParticipantID,
        subjectID: ParticipantID,
        evidenceIDs: Set<String> = [],
        notes: [String] = [],
        updatedAt: Date = Date()
    ) {
        self.issuerID = issuerID
        self.subjectID = subjectID
        self.evidenceIDs = evidenceIDs
        self.notes = notes
        self.updatedAt = updatedAt
    }
}
