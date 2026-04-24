//
//  SemanticAssertion.swift
//  SwiftAgentSymbio
//

import Foundation

public struct SemanticAssertion: Sendable, Codable, Hashable {
    public let subject: String
    public let predicate: String
    public let object: String

    public init(
        subject: String,
        predicate: String,
        object: String
    ) {
        self.subject = subject
        self.predicate = predicate
        self.object = object
    }
}

public struct SemanticClaim: Identifiable, Sendable, Codable, Hashable {
    public let id: String
    public let assertion: SemanticAssertion
    public let issuer: String
    public let observedAt: Date
    public let expiresAt: Date?
    public let confidence: Double?
    public let proof: Data?

    public init(
        id: String = UUID().uuidString,
        assertion: SemanticAssertion,
        issuer: String,
        observedAt: Date = Date(),
        expiresAt: Date? = nil,
        confidence: Double? = nil,
        proof: Data? = nil
    ) {
        self.id = id
        self.assertion = assertion
        self.issuer = issuer
        self.observedAt = observedAt
        self.expiresAt = expiresAt
        self.confidence = confidence
        self.proof = proof
    }
}
