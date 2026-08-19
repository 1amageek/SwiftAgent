//
//  ParticipantRecord.swift
//  SwiftAgentSymbio
//

import Foundation

struct ParticipantRecord: Sendable, Codable {
    var descriptor: ParticipantDescriptor
    var availability: Availability
    private var declaredAffordances: [Affordance]
    private var observedAffordances: [Affordance]
    var claims: [Claim]
    var evidence: [Evidence]
    var trustViews: [TrustView]
    var isBlocked: Bool
    var constraints: [String]

    init(
        descriptor: ParticipantDescriptor,
        availability: Availability = .available(),
        declaredAffordances: [Affordance] = [],
        observedAffordances: [Affordance] = [],
        claims: [Claim] = [],
        evidence: [Evidence] = [],
        trustViews: [TrustView] = [],
        isBlocked: Bool = false,
        constraints: [String] = []
    ) {
        self.descriptor = descriptor
        self.availability = availability
        self.declaredAffordances = declaredAffordances
        self.observedAffordances = observedAffordances
        self.claims = claims
        self.evidence = evidence
        self.trustViews = trustViews
        self.isBlocked = isBlocked
        self.constraints = constraints
    }

    var affordances: [Affordance] {
        var merged: [String: Affordance] = [:]
        for affordance in declaredAffordances {
            merged[affordance.id] = affordance
        }
        for affordance in observedAffordances {
            if let declared = merged[affordance.id] {
                merged[affordance.id] = Self.merge(
                    declared,
                    with: affordance
                )
            } else {
                merged[affordance.id] = affordance
            }
        }
        return merged.values.sorted { $0.id < $1.id }
    }

    mutating func replaceDeclaredAffordances(
        _ affordances: [Affordance]
    ) {
        declaredAffordances = affordances
    }

    mutating func recordObservedAffordance(_ affordance: Affordance) {
        observedAffordances.removeAll { $0.id == affordance.id }
        observedAffordances.append(affordance)
    }

    private static func merge(
        _ declared: Affordance,
        with observed: Affordance
    ) -> Affordance {
        Affordance(
            id: declared.id,
            ownerID: declared.ownerID,
            contract: declared.contract,
            state: mergeState(declared.state, observed.state),
            deliveryOptions: mergeDeliveryOptions(
                declared.deliveryOptions,
                observed.deliveryOptions
            ),
            evidenceIDs: declared.evidenceIDs.union(observed.evidenceIDs),
            metadata: observed.metadata.merging(declared.metadata) {
                _, declared in declared
            }
        )
    }

    private static func mergeState(
        _ declared: AffordanceState,
        _ observed: AffordanceState
    ) -> AffordanceState {
        if declared == .unavailable || observed == .unavailable {
            return .unavailable
        }
        if declared == .degraded || observed == .degraded {
            return .degraded
        }
        if declared == .unknown || observed == .unknown {
            return .unknown
        }
        return .available
    }

    private static func mergeDeliveryOptions(
        _ declared: [DeliveryOption],
        _ observed: [DeliveryOption]
    ) -> [DeliveryOption] {
        var merged: [String: DeliveryOption] = [:]
        for option in observed {
            merged[option.id] = option
        }
        for option in declared {
            merged[option.id] = option
        }
        return merged.values.sorted { $0.id < $1.id }
    }

    var view: ParticipantView {
        ParticipantView(
            descriptor: descriptor,
            availability: availability,
            affordances: affordances,
            claims: claims,
            evidence: evidence,
            trustViews: trustViews,
            isBlocked: isBlocked,
            constraints: constraints
        )
    }
}
