//
//  ParticipantID.swift
//  SwiftAgentSymbio
//

import Foundation

public struct ParticipantID: RawRepresentable, Sendable, Codable, Hashable, ExpressibleByStringLiteral, CustomStringConvertible {
    public let rawValue: String

    public init(rawValue: String) {
        self.rawValue = rawValue
    }

    public init(stringLiteral value: String) {
        self.rawValue = value
    }

    public var description: String {
        rawValue
    }
}
