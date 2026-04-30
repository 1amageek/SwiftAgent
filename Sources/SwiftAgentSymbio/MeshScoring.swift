//
//  MeshScoring.swift
//  SwiftAgentSymbio
//

import Foundation

public enum MeshMetadataKeys {
    public static let deviceType = "deviceType"
    public static let model = "model"
    public static let battery = "battery"
    public static let isCharging = "isCharging"
    public static let status = "status"
    public static let latencyMs = "latencyMs"
}

public enum MeshParticipantStatus: String, Sendable {
    case idle
    case busy

    public static func parse(_ value: String?) -> MeshParticipantStatus {
        guard let raw = value?.lowercased() else { return .idle }
        return MeshParticipantStatus(rawValue: raw) ?? .idle
    }
}

public struct MeshParticipantMetadata: Sendable {
    public let deviceType: String?
    public let model: String?
    public let battery: Double?
    public let isCharging: Bool?
    public let status: MeshParticipantStatus
    public let latencyMs: Int?

    public init(view: ParticipantView) {
        let metadata = view.descriptor.metadata
        self.deviceType = metadata[MeshMetadataKeys.deviceType]
        self.model = metadata[MeshMetadataKeys.model]
        if let value = metadata[MeshMetadataKeys.battery] {
            self.battery = Double(value)
        } else {
            self.battery = nil
        }
        if let value = metadata[MeshMetadataKeys.isCharging] {
            self.isCharging = (value as NSString).boolValue
        } else {
            self.isCharging = nil
        }
        self.status = MeshParticipantStatus.parse(metadata[MeshMetadataKeys.status])
        if let value = metadata[MeshMetadataKeys.latencyMs] {
            self.latencyMs = Int(value)
        } else {
            self.latencyMs = nil
        }
    }
}

public struct MeshTaskRequirements: Sendable {
    public var requiredCapabilities: Set<String>
    public var minBattery: Double
    public var requireCharging: Bool
    public var allowBusy: Bool
    public var maxLatencyMs: Int?

    public init(
        requiredCapabilities: Set<String> = [],
        minBattery: Double = 0.2,
        requireCharging: Bool = false,
        allowBusy: Bool = false,
        maxLatencyMs: Int? = nil
    ) {
        self.requiredCapabilities = requiredCapabilities
        self.minBattery = minBattery
        self.requireCharging = requireCharging
        self.allowBusy = allowBusy
        self.maxLatencyMs = maxLatencyMs
    }
}

public struct MeshScoreWeights: Sendable {
    public var capabilityMatch: Double
    public var batteryHigh: Double
    public var charging: Double
    public var busyPenalty: Double
    public var latencyPenaltyPer100Ms: Double

    public static let `default` = MeshScoreWeights(
        capabilityMatch: 10,
        batteryHigh: 5,
        charging: 3,
        busyPenalty: 3,
        latencyPenaltyPer100Ms: 1
    )
}

public struct ParticipantScore: Sendable {
    public let participant: ParticipantView
    public let score: Double
}

public enum MeshScorer {
    public static func score(
        participant: ParticipantView,
        requirements: MeshTaskRequirements,
        weights: MeshScoreWeights = .default
    ) -> Double {
        let metadata = MeshParticipantMetadata(view: participant)
        var score = 0.0

        let providedCapabilities = Set(participant.affordances.map(\.contract.id))
        if requirements.requiredCapabilities.isEmpty {
            score += weights.capabilityMatch
        } else if requirements.requiredCapabilities.isSubset(of: providedCapabilities) {
            score += weights.capabilityMatch
        }

        if let battery = metadata.battery, battery > 0.5 {
            score += weights.batteryHigh
        }
        if metadata.isCharging == true {
            score += weights.charging
        }
        if metadata.status == .busy {
            score -= weights.busyPenalty
        }
        if let latencyMs = metadata.latencyMs {
            score -= (Double(latencyMs) / 100.0) * weights.latencyPenaltyPer100Ms
        }

        return score
    }

    public static func selectCandidates(
        from participants: [ParticipantView],
        requirements: MeshTaskRequirements,
        topN: Int = 3,
        weights: MeshScoreWeights = .default
    ) -> [ParticipantScore] {
        let filtered = participants.filter { participant in
            guard participant.availability.state == .available || participant.availability.state == .degraded else {
                return false
            }
            guard !participant.isBlocked else {
                return false
            }
            let providedCapabilities = Set(participant.affordances.map(\.contract.id))
            guard requirements.requiredCapabilities.isSubset(of: providedCapabilities) else {
                return false
            }
            let metadata = MeshParticipantMetadata(view: participant)
            if let battery = metadata.battery, battery < requirements.minBattery {
                return false
            }
            if requirements.requireCharging && metadata.isCharging != true {
                return false
            }
            if !requirements.allowBusy && metadata.status == .busy {
                return false
            }
            if let maxLatency = requirements.maxLatencyMs,
               let latency = metadata.latencyMs,
               latency > maxLatency {
                return false
            }
            return true
        }

        return filtered
            .map { ParticipantScore(participant: $0, score: score(participant: $0, requirements: requirements, weights: weights)) }
            .sorted { $0.score > $1.score }
            .prefix(topN)
            .map { $0 }
    }
}
