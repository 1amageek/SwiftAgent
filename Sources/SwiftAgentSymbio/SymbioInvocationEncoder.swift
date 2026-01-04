//
//  SymbioInvocationEncoder.swift
//  SwiftAgentSymbio
//
//  Created by SwiftAgent.
//

import Foundation
import Distributed

/// Encoder for distributed target invocations
/// Serializes arguments to JSON for transmission
public struct SymbioInvocationEncoder: DistributedTargetInvocationEncoder {
    public typealias SerializationRequirement = Codable

    // MARK: - State

    private enum State {
        case recording
        case finished
        case consumed
    }

    private var state: State = .recording

    // MARK: - Recorded Data

    /// Encoded arguments (each argument is JSON-encoded separately)
    private var encodedArguments: [Data] = []

    /// The call target (method identifier)
    private var target: RemoteCallTarget?

    /// Generic type substitutions (stored as type names)
    private var genericSubstitutions: [String] = []

    /// Return type name (for debugging/logging)
    private var returnTypeName: String?

    /// Error type name (for debugging/logging)
    private var errorTypeName: String?

    // MARK: - JSON Encoder Configuration

    private let encoder: JSONEncoder = {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.sortedKeys]
        return encoder
    }()

    // MARK: - Initialization

    public init() {}

    // MARK: - DistributedTargetInvocationEncoder

    public mutating func recordGenericSubstitution<T>(_ type: T.Type) throws {
        guard state == .recording else {
            throw SymbioError.invalidEncoderState("Cannot record after finishing")
        }
        genericSubstitutions.append(String(describing: type))
    }

    public mutating func recordArgument<Value: SerializationRequirement>(
        _ argument: RemoteCallArgument<Value>
    ) throws {
        guard state == .recording else {
            throw SymbioError.invalidEncoderState("Cannot record after finishing")
        }

        do {
            let data = try encoder.encode(argument.value)
            encodedArguments.append(data)
        } catch {
            throw SymbioError.serializationFailed("Failed to encode argument '\(argument.label ?? "")': \(error)")
        }
    }

    public mutating func recordReturnType<R: SerializationRequirement>(_ type: R.Type) throws {
        guard state == .recording else {
            throw SymbioError.invalidEncoderState("Cannot record after finishing")
        }
        returnTypeName = String(describing: type)
    }

    public mutating func recordErrorType<E: Error>(_ type: E.Type) throws {
        guard state == .recording else {
            throw SymbioError.invalidEncoderState("Cannot record after finishing")
        }
        errorTypeName = String(describing: type)
    }

    public mutating func doneRecording() throws {
        guard state == .recording else {
            throw SymbioError.invalidEncoderState("Already finished recording")
        }
        state = .finished
    }

    // MARK: - Target Recording

    /// Record the call target (method identifier)
    /// This should be called by the actor system before making the remote call
    public mutating func recordTarget(_ target: RemoteCallTarget) {
        self.target = target
    }

    // MARK: - Payload Creation

    /// Container for all encoded invocation data
    private struct EncodedInvocation: Codable {
        let target: String
        let genericSubstitutions: [String]
        let arguments: [Data]
    }

    /// Create the combined arguments data
    /// - Returns: JSON-encoded data containing all arguments and metadata
    public mutating func makeArgumentsData() throws -> Data {
        guard state == .finished else {
            throw SymbioError.invalidEncoderState("Must call doneRecording() first")
        }

        state = .consumed

        let invocation = EncodedInvocation(
            target: target?.identifier ?? "",
            genericSubstitutions: genericSubstitutions,
            arguments: encodedArguments
        )

        do {
            return try encoder.encode(invocation)
        } catch {
            throw SymbioError.serializationFailed("Failed to encode invocation: \(error)")
        }
    }

    /// Create an invocation payload
    /// - Parameter invocationID: Unique ID for this invocation
    /// - Returns: An InvocationPayload ready for transmission
    public mutating func makePayload(invocationID: String) throws -> InvocationPayload {
        let arguments = try makeArgumentsData()
        return InvocationPayload(
            invocationID: invocationID,
            target: target?.identifier ?? "",
            arguments: arguments
        )
    }

    // MARK: - Accessors

    /// The recorded call target
    public var recordedTarget: RemoteCallTarget? {
        target
    }

    /// The target identifier string
    public var targetIdentifier: String {
        target?.identifier ?? ""
    }

    /// Number of recorded arguments
    public var argumentCount: Int {
        encodedArguments.count
    }

    /// Whether recording has been completed
    public var isFinished: Bool {
        state == .finished || state == .consumed
    }
}

// MARK: - Invocation Payload

/// Payload for invoking a remote method
public struct InvocationPayload: Codable, Sendable {
    /// Unique identifier for this invocation
    public let invocationID: String

    /// The target method identifier
    public let target: String

    /// The encoded arguments
    public let arguments: Data

    /// Timestamp when the invocation was created
    public let timestamp: Date

    public init(
        invocationID: String,
        target: String,
        arguments: Data,
        timestamp: Date = Date()
    ) {
        self.invocationID = invocationID
        self.target = target
        self.arguments = arguments
        self.timestamp = timestamp
    }
}

// MARK: - RemoteCallTarget Extension

extension RemoteCallTarget {
    /// Parse the method name from the target identifier
    /// Expected format: "ModuleName.ActorType.methodName" or just "methodName"
    public var methodName: String {
        let parts = identifier.split(separator: ".")
        return String(parts.last ?? "")
    }

    /// Full identifier including module and type
    public var fullIdentifier: String {
        identifier
    }
}
