//
//  DeliveryOption.swift
//  SwiftAgentSymbio
//

import Foundation

public enum DeliverySemantics: String, Sendable, Codable, Hashable {
    case requestResponse
    case reliableStream
    case bestEffortLatest
    case broadcast
    case localOnly
}

public enum FreshnessOrderingKind: String, Sendable, Codable, Hashable {
    case none
    case sequence
    case frameID
    case monotonicTimestamp
}

public struct FreshnessOrdering: Sendable, Codable, Hashable {
    public let kind: FreshnessOrderingKind
    public let field: String?

    public init(kind: FreshnessOrderingKind, field: String? = nil) {
        self.kind = kind
        self.field = field
    }

    public static let none = FreshnessOrdering(kind: .none)
}

public struct DeliveryOption: Identifiable, Sendable, Codable, Hashable {
    public let id: String
    public let semantics: DeliverySemantics
    public let maximumLatency: TimeInterval?
    public let expiry: TimeInterval?
    public let freshnessOrdering: FreshnessOrdering
    public let metadata: [String: String]

    public init(
        id: String = UUID().uuidString,
        semantics: DeliverySemantics,
        maximumLatency: TimeInterval? = nil,
        expiry: TimeInterval? = nil,
        freshnessOrdering: FreshnessOrdering = .none,
        metadata: [String: String] = [:]
    ) {
        self.id = id
        self.semantics = semantics
        self.maximumLatency = maximumLatency
        self.expiry = expiry
        self.freshnessOrdering = freshnessOrdering
        self.metadata = metadata
    }
}
