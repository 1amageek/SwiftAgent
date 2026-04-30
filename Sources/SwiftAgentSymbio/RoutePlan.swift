//
//  RoutePlan.swift
//  SwiftAgentSymbio
//

import Foundation

public enum PolicyDecisionState: String, Sendable, Codable, Hashable {
    case approved
    case denied
    case requiresApproval
}

public struct PolicyDecision: Sendable, Codable, Hashable {
    public let state: PolicyDecisionState
    public let policyIDs: Set<String>
    public let reasons: [String]
    public let decidedAt: Date
    public let expiresAt: Date?

    public init(
        state: PolicyDecisionState,
        policyIDs: Set<String>,
        reasons: [String] = [],
        decidedAt: Date = Date(),
        expiresAt: Date? = nil
    ) {
        self.state = state
        self.policyIDs = policyIDs
        self.reasons = reasons
        self.decidedAt = decidedAt
        self.expiresAt = expiresAt
    }
}

public enum RoutePlanStepKind: String, Sendable, Codable, Hashable {
    case send
    case broadcast
    case mediate
    case reject
}

public struct RoutePlanStep: Identifiable, Sendable, Codable, Hashable {
    public let id: String
    public let kind: RoutePlanStepKind
    public let participantID: ParticipantID?
    public let affordanceID: String?
    public let deliveryOption: DeliveryOption?
    public let reasons: [String]
    public let risks: [String]

    public init(
        id: String = UUID().uuidString,
        kind: RoutePlanStepKind,
        participantID: ParticipantID? = nil,
        affordanceID: String? = nil,
        deliveryOption: DeliveryOption? = nil,
        reasons: [String] = [],
        risks: [String] = []
    ) {
        self.id = id
        self.kind = kind
        self.participantID = participantID
        self.affordanceID = affordanceID
        self.deliveryOption = deliveryOption
        self.reasons = reasons
        self.risks = risks
    }
}

public struct RoutePlan: Identifiable, Sendable, Codable, Hashable {
    public let id: String
    public let messageID: String
    public let steps: [RoutePlanStep]
    public let requiredPolicies: Set<String>
    public let policyDecision: PolicyDecision
    public let evidenceInputs: Set<String>
    public let createdAt: Date
    public let expiresAt: Date?

    public init(
        id: String = UUID().uuidString,
        messageID: String,
        steps: [RoutePlanStep],
        requiredPolicies: Set<String> = [],
        policyDecision: PolicyDecision,
        evidenceInputs: Set<String> = [],
        createdAt: Date = Date(),
        expiresAt: Date? = nil
    ) {
        self.id = id
        self.messageID = messageID
        self.steps = steps
        self.requiredPolicies = requiredPolicies
        self.policyDecision = policyDecision
        self.evidenceInputs = evidenceInputs
        self.createdAt = createdAt
        self.expiresAt = expiresAt
    }

    public var isPreExecutionAuthorized: Bool {
        policyDecision.state == .approved && steps.allSatisfy { $0.kind != .reject }
    }

    public func withPolicyDecision(_ decision: PolicyDecision) -> RoutePlan {
        RoutePlan(
            id: id,
            messageID: messageID,
            steps: steps,
            requiredPolicies: requiredPolicies,
            policyDecision: decision,
            evidenceInputs: evidenceInputs,
            createdAt: createdAt,
            expiresAt: expiresAt
        )
    }

    public func policyRequest() -> PolicyRequest {
        PolicyRequest(
            routePlanID: id,
            messageID: messageID,
            policyIDs: requiredPolicies,
            participantIDs: Set(steps.compactMap(\.participantID)),
            evidenceInputs: evidenceInputs
        )
    }
}
