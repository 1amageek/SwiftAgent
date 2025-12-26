// MARK: - SymbioResultHandler
// Result Handler for SymbioActorSystem
// Handles distributed actor invocation results

import Foundation
import Distributed

/// Handler for distributed target invocation results
/// Converts Swift results to InvocationResponse
public struct SymbioResultHandler: DistributedTargetInvocationResultHandler {
    public typealias SerializationRequirement = Codable

    // MARK: - Properties

    /// The invocation ID for correlation
    public let invocationID: String

    /// Callback to send the response
    private let sendResponse: @Sendable (InvocationResponse) async throws -> Void

    // MARK: - JSON Encoder Configuration

    private let encoder: JSONEncoder = {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.sortedKeys]
        return encoder
    }()

    // MARK: - Initialization

    /// Create a result handler
    /// - Parameters:
    ///   - invocationID: The invocation ID for correlation
    ///   - sendResponse: Callback to send the response
    public init(
        invocationID: String,
        sendResponse: @escaping @Sendable (InvocationResponse) async throws -> Void
    ) {
        self.invocationID = invocationID
        self.sendResponse = sendResponse
    }

    // MARK: - DistributedTargetInvocationResultHandler

    public func onReturn<Success: SerializationRequirement>(value: Success) async throws {
        let resultData: Data
        do {
            resultData = try encoder.encode(value)
        } catch {
            // If encoding fails, send an error response
            let errorResponse = InvocationResponse(
                invocationID: invocationID,
                success: false,
                errorCode: SymbioErrorCode.serializationFailed.rawValue,
                errorMessage: "Failed to encode result: \(error)"
            )
            try await sendResponse(errorResponse)
            return
        }

        let response = InvocationResponse(
            invocationID: invocationID,
            success: true,
            result: resultData
        )
        try await sendResponse(response)
    }

    public func onReturnVoid() async throws {
        let response = InvocationResponse(
            invocationID: invocationID,
            success: true,
            result: nil
        )
        try await sendResponse(response)
    }

    public func onThrow<Err: Error>(error: Err) async throws {
        let errorCode: Int
        let errorMessage: String

        // Try to extract more specific error information
        if let symbioError = error as? SymbioError {
            errorCode = symbioErrorCode(symbioError)
            errorMessage = symbioError.errorDescription ?? String(describing: error)
        } else {
            errorCode = SymbioErrorCode.invocationFailed.rawValue
            errorMessage = String(describing: error)
        }

        let response = InvocationResponse(
            invocationID: invocationID,
            success: false,
            errorCode: errorCode,
            errorMessage: errorMessage
        )
        try await sendResponse(response)
    }

    // MARK: - Error Code Mapping

    private func symbioErrorCode(_ error: SymbioError) -> Int {
        switch error {
        case .notStarted, .alreadyStarted:
            return SymbioErrorCode.internalError.rawValue
        case .actorNotFound, .actorNotLocal:
            return SymbioErrorCode.notFound.rawValue
        case .invalidAddress:
            return SymbioErrorCode.invalidArgument.rawValue
        case .invocationFailed:
            return SymbioErrorCode.invocationFailed.rawValue
        case .timeout:
            return SymbioErrorCode.timeout.rawValue
        case .serializationFailed:
            return SymbioErrorCode.serializationFailed.rawValue
        case .deserializationFailed:
            return SymbioErrorCode.deserializationFailed.rawValue
        case .invalidEncoderState, .noMoreArguments, .invalidArgumentData:
            return SymbioErrorCode.invalidArgument.rawValue
        case .noTransportAvailable:
            return SymbioErrorCode.internalError.rawValue
        case .invalidState:
            return SymbioErrorCode.internalError.rawValue
        }
    }
}

// MARK: - Result Decoding

extension SymbioResultHandler {

    /// Decode a result from an InvocationResponse
    /// - Parameters:
    ///   - response: The response
    ///   - type: The expected result type
    /// - Returns: The decoded result
    public static func decodeResult<T: Codable>(
        from response: InvocationResponse,
        as type: T.Type
    ) throws -> T {
        guard response.success else {
            throw SymbioError.invocationFailed(
                response.errorMessage ?? "Unknown error (code: \(response.errorCode ?? 0))"
            )
        }

        guard let resultData = response.result else {
            throw SymbioError.deserializationFailed("No result data in successful response")
        }

        do {
            let decoder = JSONDecoder()
            decoder.dateDecodingStrategy = .iso8601
            return try decoder.decode(T.self, from: resultData)
        } catch {
            throw SymbioError.deserializationFailed("Failed to decode result: \(error)")
        }
    }

    /// Check if a response indicates success (for void returns)
    /// - Parameter response: The response
    /// - Throws: SymbioError if the response indicates failure
    public static func checkVoidResult(from response: InvocationResponse) throws {
        guard response.success else {
            throw SymbioError.invocationFailed(
                response.errorMessage ?? "Unknown error (code: \(response.errorCode ?? 0))"
            )
        }
    }
}
