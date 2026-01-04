//
//  Address.swift
//  SwiftAgentSymbio
//
//  Created by SwiftAgent.
//

import Foundation
import Distributed

/// Network address for use with SymbioActorSystem
///
/// Address is a simple, unique network endpoint following DNS principles:
/// - The address is just a unique identifier (32 bytes)
/// - The system (SymbioActorSystem) handles resolution and routing
/// - Locality is determined by the system's registry, not by the address
///
/// This design mirrors Bonjour/DNS where:
/// - Addresses are simple identifiers (like IP addresses)
/// - Resolution is handled by the DNS system
/// - Routing is transparent to the client
public struct Address: Hashable, Sendable, CustomStringConvertible {

    // MARK: - Properties

    /// Raw bytes of the address (32 bytes)
    /// This is the only data the address carries - no routing information
    public let rawValue: Data

    // MARK: - Initialization

    /// Create a new random address
    public init() {
        var bytes = [UInt8](repeating: 0, count: 32)
        _ = SecRandomCopyBytes(kSecRandomDefault, bytes.count, &bytes)
        self.rawValue = Data(bytes)
    }

    /// Create an address from raw data
    /// - Parameter rawValue: The raw bytes (must be 32 bytes)
    public init(rawValue: Data) {
        precondition(rawValue.count == 32, "Address must be 32 bytes")
        self.rawValue = rawValue
    }

    /// Create an address from a hex string
    /// - Parameter hexString: The hex-encoded address
    public init(hexString: String) throws {
        guard let data = Data(hexString: hexString), data.count == 32 else {
            throw SymbioError.invalidAddress("Invalid hex string: \(hexString)")
        }
        self.rawValue = data
    }

    /// Create an address from a UUID (expands to 32 bytes)
    /// - Parameter uuid: The UUID to use
    public init(uuid: UUID) {
        var data = Data(count: 32)
        let uuidBytes = withUnsafeBytes(of: uuid.uuid) { Data($0) }
        data.replaceSubrange(0..<16, with: uuidBytes)
        // Fill remaining 16 bytes with zeros
        self.rawValue = data
    }

    // MARK: - Properties

    /// Hex string representation
    public var hexString: String {
        rawValue.map { String(format: "%02x", $0) }.joined()
    }

    /// Short string for display (first 8 characters)
    public var shortString: String {
        String(hexString.prefix(8))
    }

    // MARK: - CustomStringConvertible

    public var description: String {
        "Address(\(shortString))"
    }

    // MARK: - Hashable

    public func hash(into hasher: inout Hasher) {
        hasher.combine(rawValue)
    }

    public static func == (lhs: Address, rhs: Address) -> Bool {
        lhs.rawValue == rhs.rawValue
    }
}

// MARK: - Codable

extension Address: Codable {
    public init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        let hexString = try container.decode(String.self)
        guard let data = Data(hexString: hexString), data.count == 32 else {
            throw DecodingError.dataCorruptedError(
                in: container,
                debugDescription: "Invalid hex string for Address"
            )
        }
        self.rawValue = data
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(hexString)
    }
}

// MARK: - Data Extension

extension Data {
    /// Initialize Data from a hex string
    init?(hexString: String) {
        let hex = hexString.dropFirst(hexString.hasPrefix("0x") ? 2 : 0)
        guard hex.count % 2 == 0 else { return nil }

        var data = Data(capacity: hex.count / 2)
        var index = hex.startIndex

        while index < hex.endIndex {
            let nextIndex = hex.index(index, offsetBy: 2)
            guard let byte = UInt8(hex[index..<nextIndex], radix: 16) else {
                return nil
            }
            data.append(byte)
            index = nextIndex
        }

        self = data
    }
}
