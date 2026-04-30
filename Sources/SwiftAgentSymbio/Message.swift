//
//  Message.swift
//  SwiftAgentSymbio
//

import Foundation

public enum MessageAddressing: Sendable, Codable, Hashable {
    case direct(ParticipantID)
    case group(Set<ParticipantID>)
    case open
}

public struct Message: Identifiable, Sendable, Codable, Hashable {
    public let id: String
    public let senderID: ParticipantID
    public let addressing: MessageAddressing
    public let representation: MessageRepresentation
    public let payload: Data
    public let intent: String?
    public let createdAt: Date
    public let expiresAt: Date?
    public let metadata: [String: String]

    public init(
        id: String = UUID().uuidString,
        senderID: ParticipantID,
        addressing: MessageAddressing,
        representation: MessageRepresentation,
        payload: Data,
        intent: String? = nil,
        createdAt: Date = Date(),
        expiresAt: Date? = nil,
        metadata: [String: String] = [:]
    ) {
        self.id = id
        self.senderID = senderID
        self.addressing = addressing
        self.representation = representation
        self.payload = payload
        self.intent = intent
        self.createdAt = createdAt
        self.expiresAt = expiresAt
        self.metadata = metadata
    }
}
