//
//  Evidence.swift
//  SwiftAgentSymbio
//

import Foundation

public enum EvidenceKind: String, Sendable, Codable, Hashable {
    case observation
    case successfulInvocation
    case failedInvocation
    case policyDecision
    case aggregateRollup
}

public struct Evidence: Identifiable, Sendable, Codable, Hashable {
    public let id: String
    public let subjectID: ParticipantID
    public let kind: EvidenceKind
    public let message: String?
    public let recordedAt: Date
    public let expiresAt: Date?
    public let metadata: [String: String]

    public init(
        id: String = UUID().uuidString,
        subjectID: ParticipantID,
        kind: EvidenceKind,
        message: String? = nil,
        recordedAt: Date = Date(),
        expiresAt: Date? = nil,
        metadata: [String: String] = [:]
    ) {
        self.id = id
        self.subjectID = subjectID
        self.kind = kind
        self.message = message
        self.recordedAt = recordedAt
        self.expiresAt = expiresAt
        self.metadata = metadata
    }
}
