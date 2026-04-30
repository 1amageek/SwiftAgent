//
//  CoordinationSurface.swift
//  SwiftAgentSymbio
//

import Foundation

public struct ThreadID: RawRepresentable, Sendable, Codable, Hashable, ExpressibleByStringLiteral {
    public let rawValue: String

    public init(rawValue: String) {
        self.rawValue = rawValue
    }

    public init(stringLiteral value: String) {
        self.rawValue = value
    }
}

public enum CoordinationMode: String, Sendable, Codable, Hashable {
    case none
    case thread
    case board
    case sharedState
}

public struct CoordinationNeed: Sendable, Codable, Hashable {
    public let participantCount: Int
    public let requiresSharedState: Bool
    public let requiresDurableHistory: Bool
    public let maximumLatency: TimeInterval?

    public init(
        participantCount: Int,
        requiresSharedState: Bool = false,
        requiresDurableHistory: Bool = false,
        maximumLatency: TimeInterval? = nil
    ) {
        self.participantCount = participantCount
        self.requiresSharedState = requiresSharedState
        self.requiresDurableHistory = requiresDurableHistory
        self.maximumLatency = maximumLatency
    }
}

public struct CoordinationSurface: Identifiable, Sendable, Codable, Hashable {
    public let id: String
    public let mode: CoordinationMode
    public let participantIDs: Set<ParticipantID>
    public let threadID: ThreadID?
    public let metadata: [String: String]

    public init(
        id: String = UUID().uuidString,
        mode: CoordinationMode,
        participantIDs: Set<ParticipantID>,
        threadID: ThreadID? = nil,
        metadata: [String: String] = [:]
    ) {
        self.id = id
        self.mode = mode
        self.participantIDs = participantIDs
        self.threadID = threadID
        self.metadata = metadata
    }
}
