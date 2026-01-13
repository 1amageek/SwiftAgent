//
//  MeshScoring.swift
//  SwiftAgentSymbio
//
//  Scoring and selection utilities for mesh task dispatch.
//

import Foundation

// MARK: - Mesh Metadata Keys

public enum MeshMetadataKeys {
    public static let deviceType = "deviceType"
    public static let model = "model"
    public static let battery = "battery"          // 0.0 - 1.0
    public static let isCharging = "isCharging"    // "true" / "false"
    public static let status = "status"            // "idle" / "busy"
    public static let latencyMs = "latencyMs"      // Int as String
}

// MARK: - Mesh Status

public enum MeshMemberStatus: String, Sendable {
    case idle
    case busy

    public static func parse(_ value: String?) -> MeshMemberStatus {
        guard let raw = value?.lowercased() else { return .idle }
        return MeshMemberStatus(rawValue: raw) ?? .idle
    }
}

// MARK: - Member Metadata

public struct MeshMemberMetadata: Sendable {
    public let deviceType: String?
    public let model: String?
    public let battery: Double?
    public let isCharging: Bool?
    public let status: MeshMemberStatus
    public let latencyMs: Int?

    public init(member: Member) {
        let metadata = member.metadata
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
        self.status = MeshMemberStatus.parse(metadata[MeshMetadataKeys.status])
        if let value = metadata[MeshMetadataKeys.latencyMs] {
            self.latencyMs = Int(value)
        } else {
            self.latencyMs = nil
        }
    }
}

// MARK: - Task Requirements

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

// MARK: - Scoring

public struct MeshScoreWeights: Sendable {
    public var capabilityMatch: Double
    public var batteryHigh: Double
    public var charging: Double
    public var busyPenalty: Double
    public var latencyPenaltyPer100Ms: Double

    public static let `default` = MeshScoreWeights(
        capabilityMatch: 10.0,
        batteryHigh: 5.0,
        charging: 3.0,
        busyPenalty: 3.0,
        latencyPenaltyPer100Ms: 1.0
    )
}

public struct MemberScore: Sendable {
    public let member: Member
    public let score: Double
}

public enum MeshScorer {

    public static func score(
        member: Member,
        requirements: MeshTaskRequirements,
        weights: MeshScoreWeights = .default
    ) -> Double {
        let meta = MeshMemberMetadata(member: member)

        var score = 0.0

        // Capability match
        if requirements.requiredCapabilities.isEmpty {
            score += weights.capabilityMatch
        } else {
            let matchesAll = requirements.requiredCapabilities.allSatisfy { cap in
                member.canProvide(cap)
            }
            score += matchesAll ? weights.capabilityMatch : 0.0
        }

        // Battery
        if let battery = meta.battery, battery > 0.5 {
            score += weights.batteryHigh
        }

        // Charging
        if meta.isCharging == true {
            score += weights.charging
        }

        // Busy penalty
        if meta.status == .busy {
            score -= weights.busyPenalty
        }

        // Latency penalty
        if let latencyMs = meta.latencyMs {
            score -= (Double(latencyMs) / 100.0) * weights.latencyPenaltyPer100Ms
        }

        return score
    }

    public static func selectCandidates(
        from members: [Member],
        requirements: MeshTaskRequirements,
        topN: Int = 3,
        weights: MeshScoreWeights = .default
    ) -> [MemberScore] {
        let filtered = members.filter { member in
            guard member.isAvailable else { return false }

            // Capability filter
            for cap in requirements.requiredCapabilities {
                if !member.canProvide(cap) { return false }
            }

            let meta = MeshMemberMetadata(member: member)

            if let battery = meta.battery, battery < requirements.minBattery {
                return false
            }

            if requirements.requireCharging && meta.isCharging != true {
                return false
            }

            if !requirements.allowBusy && meta.status == .busy {
                return false
            }

            if let maxLatency = requirements.maxLatencyMs,
               let latency = meta.latencyMs,
               latency > maxLatency {
                return false
            }

            return true
        }

        let scored = filtered.map { member in
            MemberScore(
                member: member,
                score: score(member: member, requirements: requirements, weights: weights)
            )
        }

        return scored.sorted { $0.score > $1.score }.prefix(topN).map { $0 }
    }
}

