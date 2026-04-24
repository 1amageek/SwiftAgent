//
//  PeerObservation.swift
//  SwiftAgentSymbio
//

import Foundation

public enum PeerObservationKind: String, Sendable, Codable {
    case discovered
    case updated
    case becameAvailable
    case becameUnavailable
    case invocationSucceeded
    case invocationFailed
    case blocked
    case forgotten
}

public struct PeerObservation: Identifiable, Sendable, Codable, Hashable {
    public let id: String
    public let peerID: String
    public let kind: PeerObservationKind
    public let message: String?
    public let observedAt: Date

    public init(
        id: String = UUID().uuidString,
        peerID: String,
        kind: PeerObservationKind,
        message: String? = nil,
        observedAt: Date = Date()
    ) {
        self.id = id
        self.peerID = peerID
        self.kind = kind
        self.message = message
        self.observedAt = observedAt
    }
}
