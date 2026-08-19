import Foundation
import NetworkingCore
import NetworkingFoundationCompat
import SwiftAgentSymbio

struct SymbioWireInvocationReply: Codable, Sendable {
    let invocationID: String
    let result: Data?
    let failure: SymbioInvocationFailure?

    init(_ reply: SymbioInvocationReply) {
        self.invocationID = reply.invocationID
        switch reply.outcome {
        case .success(let result):
            // Codable is the wire boundary; the core keeps payloads in OwnedBytes.
            self.result = result.map { Data(copying: $0) }
            self.failure = nil
        case .failure(let failure):
            self.result = nil
            self.failure = failure
        }
    }

    func validated() throws -> Self {
        guard !invocationID.trimmingCharacters(
            in: .whitespacesAndNewlines
        ).isEmpty else {
            throw PeerConnectivitySymbioError.invalidWireMessage(
                "Reply invocation ID must not be empty"
            )
        }
        if let failure {
            guard result == nil else {
                throw PeerConnectivitySymbioError.invalidWireMessage(
                    "Failure reply also contained a result"
                )
            }
        }
        return self
    }

    func value() throws -> SymbioInvocationReply {
        let validated = try validated()
        if let failure = validated.failure {
            return SymbioInvocationReply(
                invocationID: validated.invocationID,
                outcome: .failure(failure)
            )
        }
        return .success(
            invocationID: validated.invocationID,
            result: validated.result.map { OwnedBytes(copying: $0) }
        )
    }
}
