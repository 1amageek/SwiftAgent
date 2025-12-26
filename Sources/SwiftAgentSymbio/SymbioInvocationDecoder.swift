// MARK: - SymbioInvocationDecoder
// Invocation Decoder for SymbioActorSystem
// Decodes distributed actor invocation arguments

import Foundation
import Distributed

/// Decoder for distributed target invocations
/// Deserializes arguments from transport payloads
public struct SymbioInvocationDecoder: DistributedTargetInvocationDecoder {
    public typealias SerializationRequirement = Codable

    // MARK: - Decoded Data

    /// The target method identifier
    public let target: String

    /// Generic type substitutions (as type name strings)
    private let genericSubstitutions: [String]

    /// Encoded arguments
    private var arguments: [Data]

    /// Current argument index
    private var currentIndex: Int = 0

    // MARK: - JSON Decoder Configuration

    private let decoder: JSONDecoder = {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }()

    // MARK: - Initialization

    /// Container for all encoded invocation data
    private struct EncodedInvocation: Codable {
        let target: String
        let genericSubstitutions: [String]
        let arguments: [Data]
    }

    /// Initialize from encoded arguments data
    /// - Parameter argumentsData: The combined arguments data
    public init(argumentsData: Data) throws {
        do {
            let invocation = try JSONDecoder().decode(EncodedInvocation.self, from: argumentsData)
            self.target = invocation.target
            self.genericSubstitutions = invocation.genericSubstitutions
            self.arguments = invocation.arguments
        } catch {
            throw SymbioError.deserializationFailed("Failed to decode invocation: \(error)")
        }
    }

    /// Initialize from an InvocationPayload
    /// - Parameter payload: The invocation payload
    public init(from payload: InvocationPayload) throws {
        try self.init(argumentsData: payload.arguments)
    }

    /// Initialize with explicit components (for testing)
    public init(target: String, genericSubstitutions: [String] = [], arguments: [Data]) {
        self.target = target
        self.genericSubstitutions = genericSubstitutions
        self.arguments = arguments
    }

    // MARK: - DistributedTargetInvocationDecoder

    public mutating func decodeGenericSubstitutions() throws -> [Any.Type] {
        // Generic substitutions are stored as type name strings
        // In a real implementation, you would need a type registry to look these up
        // For now, we return an empty array as the exact types are not resolvable
        // from strings without additional infrastructure
        return []
    }

    public mutating func decodeNextArgument<Argument: SerializationRequirement>() throws -> Argument {
        guard currentIndex < arguments.count else {
            throw SymbioError.noMoreArguments
        }

        let data = arguments[currentIndex]
        currentIndex += 1

        do {
            return try decoder.decode(Argument.self, from: data)
        } catch {
            throw SymbioError.invalidArgumentData("Failed to decode argument at index \(currentIndex - 1): \(error)")
        }
    }

    public mutating func decodeReturnType() throws -> Any.Type? {
        // Return type is not encoded in the invocation
        // The caller already knows the expected return type
        return nil
    }

    public mutating func decodeErrorType() throws -> Any.Type? {
        // Error type is not encoded in the invocation
        // The caller already knows the expected error type
        return nil
    }

    // MARK: - Accessors

    /// Number of arguments available
    public var argumentCount: Int {
        arguments.count
    }

    /// Number of arguments remaining
    public var remainingArgumentCount: Int {
        arguments.count - currentIndex
    }

    /// Whether all arguments have been decoded
    public var isComplete: Bool {
        currentIndex >= arguments.count
    }

    /// Reset the decoder to start from the first argument
    public mutating func reset() {
        currentIndex = 0
    }
}

// MARK: - Convenience Extensions

extension SymbioInvocationDecoder {

    /// Peek at the next argument without consuming it
    /// - Returns: The decoded argument, or nil if no more arguments
    public func peekNextArgument<Argument: Codable>() -> Argument? {
        guard currentIndex < arguments.count else { return nil }
        let data = arguments[currentIndex]
        return try? JSONDecoder().decode(Argument.self, from: data)
    }

    /// Decode all remaining arguments as an array
    /// - Returns: Array of decoded arguments
    public mutating func decodeRemainingArguments<Argument: Codable>() throws -> [Argument] {
        var result: [Argument] = []
        while currentIndex < arguments.count {
            result.append(try decodeNextArgument())
        }
        return result
    }
}
