//
//  CapabilityContract.swift
//  SwiftAgentSymbio
//

import Foundation

public enum SideEffectLevel: String, Sendable, Codable, Hashable {
    case none
    case localState
    case network
    case physical
    case safetyCritical
}

public struct CapabilityContract: Identifiable, Sendable, Codable, Hashable {
    public let id: String
    public let purpose: String?
    public let input: MessageRepresentation
    public let output: MessageRepresentation?
    public let sideEffectLevel: SideEffectLevel
    public let requiredPolicies: Set<String>

    public init(
        id: String,
        purpose: String? = nil,
        input: MessageRepresentation,
        output: MessageRepresentation? = nil,
        sideEffectLevel: SideEffectLevel = .none,
        requiredPolicies: Set<String> = []
    ) {
        self.id = id
        self.purpose = purpose
        self.input = input
        self.output = output
        self.sideEffectLevel = sideEffectLevel
        self.requiredPolicies = requiredPolicies
    }
}
