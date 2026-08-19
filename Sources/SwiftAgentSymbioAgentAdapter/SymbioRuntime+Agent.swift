import Foundation
import NetworkingCore
import NetworkingFoundationCompat
import SwiftAgentSymbio

extension SymbioRuntime {
    @discardableResult
    public func send<Signal: Sendable & Encodable>(
        _ signal: Signal,
        to participantID: ParticipantID,
        perception: String,
        from sender: ParticipantHandle,
        authorizer: (any PolicyAuthorizer)? = nil,
        timeout: Duration = .seconds(30)
    ) async throws -> Data? {
        // JSON and Foundation Data are confined to the SwiftAgent adapter.
        let encoded = try JSONEncoder().encode(signal)
        let result = try await invoke(
            "\(AgentCapabilityNamespace.perception).\(perception)",
            on: participantID,
            representation: .typedPayload(schema: perception),
            with: OwnedBytes(copying: encoded),
            from: sender,
            authorizer: authorizer,
            timeout: timeout
        )
        return result.map { Data(copying: $0) }
    }

    @discardableResult
    public func invokeAgentCapability(
        _ capability: String,
        on participantID: ParticipantID,
        representation: MessageRepresentation,
        with arguments: Data,
        from sender: ParticipantHandle,
        authorizer: (any PolicyAuthorizer)? = nil,
        timeout: Duration = .seconds(30)
    ) async throws -> Data? {
        let result = try await invoke(
            capability,
            on: participantID,
            representation: representation,
            with: OwnedBytes(copying: arguments),
            from: sender,
            authorizer: authorizer,
            timeout: timeout
        )
        return result.map { Data(copying: $0) }
    }
}
