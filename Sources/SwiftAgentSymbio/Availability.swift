//
//  Availability.swift
//  SwiftAgentSymbio
//

import Foundation

public enum AvailabilityState: String, Sendable, Codable, Hashable {
    case available
    case degraded
    case unavailable
    case unknown
}

public struct Availability: Sendable, Codable, Hashable {
    public let state: AvailabilityState
    public let reason: String?
    public let observedAt: Date
    public let expiresAt: Date?

    public init(
        state: AvailabilityState,
        reason: String? = nil,
        observedAt: Date = Date(),
        expiresAt: Date? = nil
    ) {
        self.state = state
        self.reason = reason
        self.observedAt = observedAt
        self.expiresAt = expiresAt
    }

    public static func available(observedAt: Date = Date()) -> Availability {
        Availability(state: .available, observedAt: observedAt)
    }

    public static func unavailable(reason: String? = nil, observedAt: Date = Date()) -> Availability {
        Availability(state: .unavailable, reason: reason, observedAt: observedAt)
    }

    public static func unknown(reason: String? = nil, observedAt: Date = Date()) -> Availability {
        Availability(state: .unknown, reason: reason, observedAt: observedAt)
    }
}
