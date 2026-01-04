//
//  SymbioError.swift
//  SwiftAgentSymbio
//
//  Created by SwiftAgent.
//

import Foundation

/// Errors that can occur in the SymbioActorSystem
public enum SymbioError: Error, LocalizedError, Sendable {

    // MARK: - Lifecycle Errors

    /// The system has not been started
    case notStarted

    /// The system is already started
    case alreadyStarted

    // MARK: - Actor Resolution Errors

    /// The actor could not be found
    case actorNotFound(Address)

    /// The actor is not local to this system
    case actorNotLocal(Address)

    /// Invalid address format
    case invalidAddress(String)

    // MARK: - Invocation Errors

    /// Remote invocation failed
    case invocationFailed(String)

    /// Invocation timed out
    case timeout

    // MARK: - Serialization Errors

    /// Failed to serialize invocation arguments
    case serializationFailed(String)

    /// Failed to deserialize invocation result
    case deserializationFailed(String)

    // MARK: - Encoding/Decoding Errors

    /// Encoder is in an invalid state
    case invalidEncoderState(String)

    /// Decoder ran out of arguments
    case noMoreArguments

    /// Decoder received invalid data
    case invalidArgumentData(String)

    // MARK: - System Errors

    /// No transport is available
    case noTransportAvailable

    /// Invalid state encountered
    case invalidState(String)

    // MARK: - LocalizedError

    public var errorDescription: String? {
        switch self {
        case .notStarted:
            return "SymbioActorSystem has not been started"
        case .alreadyStarted:
            return "SymbioActorSystem is already started"
        case .actorNotFound(let id):
            return "Actor not found: \(id)"
        case .actorNotLocal(let id):
            return "Actor is not local: \(id)"
        case .invalidAddress(let reason):
            return "Invalid address: \(reason)"
        case .invocationFailed(let reason):
            return "Invocation failed: \(reason)"
        case .timeout:
            return "Operation timed out"
        case .serializationFailed(let reason):
            return "Serialization failed: \(reason)"
        case .deserializationFailed(let reason):
            return "Deserialization failed: \(reason)"
        case .invalidEncoderState(let reason):
            return "Invalid encoder state: \(reason)"
        case .noMoreArguments:
            return "No more arguments to decode"
        case .invalidArgumentData(let reason):
            return "Invalid argument data: \(reason)"
        case .noTransportAvailable:
            return "No transport available"
        case .invalidState(let reason):
            return "Invalid state: \(reason)"
        }
    }
}

// MARK: - Invocation Response

/// Response from a remote invocation
public struct InvocationResponse: Codable, Sendable {
    /// Unique identifier correlating to the invocation
    public let invocationID: String

    /// Whether the invocation succeeded
    public let success: Bool

    /// The result data (if successful)
    public let result: Data?

    /// Error code (if failed)
    public let errorCode: Int?

    /// Error message (if failed)
    public let errorMessage: String?

    public init(
        invocationID: String,
        success: Bool,
        result: Data? = nil,
        errorCode: Int? = nil,
        errorMessage: String? = nil
    ) {
        self.invocationID = invocationID
        self.success = success
        self.result = result
        self.errorCode = errorCode
        self.errorMessage = errorMessage
    }

    /// Create a successful response
    public static func success(invocationID: String, result: Data?) -> InvocationResponse {
        InvocationResponse(invocationID: invocationID, success: true, result: result)
    }

    /// Create a failed response
    public static func failure(invocationID: String, code: Int, message: String) -> InvocationResponse {
        InvocationResponse(
            invocationID: invocationID,
            success: false,
            errorCode: code,
            errorMessage: message
        )
    }
}

// MARK: - Error Codes

/// Standard error codes for invocation failures
public enum SymbioErrorCode: Int, Sendable {
    case unknown = 0
    case notFound = 1
    case timeout = 2
    case serializationFailed = 3
    case deserializationFailed = 4
    case invocationFailed = 5
    case unauthorized = 6
    case invalidArgument = 7
    case internalError = 8
}
