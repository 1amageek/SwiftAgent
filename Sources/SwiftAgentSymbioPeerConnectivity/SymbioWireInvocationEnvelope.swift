import Foundation
import NetworkingCore
import NetworkingFoundationCompat
import SwiftAgentSymbio

struct SymbioWireInvocationEnvelope: Codable, Sendable {
    let invocationID: String
    let senderID: ParticipantID
    let recipientID: ParticipantID
    let capability: String
    let representation: MessageRepresentation
    let arguments: Data
    let budgetSeconds: Int64
    let budgetAttoseconds: Int64

    init(_ envelope: SymbioInvocationEnvelope) {
        let components = envelope.executionBudget.components
        self.invocationID = envelope.invocationID
        self.senderID = envelope.senderID
        self.recipientID = envelope.recipientID
        self.capability = envelope.capability
        self.representation = envelope.representation
        // Codable is the wire boundary; the core keeps payloads in OwnedBytes.
        self.arguments = Data(copying: envelope.arguments)
        self.budgetSeconds = components.seconds
        self.budgetAttoseconds = components.attoseconds
    }

    func validated() throws -> Self {
        guard !invocationID.trimmingCharacters(
            in: .whitespacesAndNewlines
        ).isEmpty else {
            throw PeerConnectivitySymbioError.invalidWireMessage(
                "Invocation ID must not be empty"
            )
        }
        guard !senderID.rawValue.trimmingCharacters(
            in: .whitespacesAndNewlines
        ).isEmpty,
        !recipientID.rawValue.trimmingCharacters(
            in: .whitespacesAndNewlines
        ).isEmpty else {
            throw PeerConnectivitySymbioError.invalidWireMessage(
                "Invocation participant IDs must not be empty"
            )
        }
        guard !capability.trimmingCharacters(
            in: .whitespacesAndNewlines
        ).isEmpty else {
            throw PeerConnectivitySymbioError.invalidWireMessage(
                "Invocation capability must not be empty"
            )
        }
        guard !representation.contentType.trimmingCharacters(
            in: .whitespacesAndNewlines
        ).isEmpty else {
            throw PeerConnectivitySymbioError.invalidWireMessage(
                "Invocation representation content type must not be empty"
            )
        }
        if representation.kind == .typedPayload {
            guard let schema = representation.schema,
                  !schema.trimmingCharacters(
                    in: .whitespacesAndNewlines
                  ).isEmpty else {
                throw PeerConnectivitySymbioError.invalidWireMessage(
                    "Typed invocation representation must declare a schema"
                )
            }
        }
        let budget = Duration(
            secondsComponent: budgetSeconds,
            attosecondsComponent: budgetAttoseconds
        )
        guard budget > .zero else {
            throw PeerConnectivitySymbioError.invalidWireMessage(
                "Execution budget must be greater than zero"
            )
        }
        return self
    }

    func value() throws -> SymbioInvocationEnvelope {
        let validated = try validated()
        let budget = Duration(
            secondsComponent: validated.budgetSeconds,
            attosecondsComponent: validated.budgetAttoseconds
        )
        return SymbioInvocationEnvelope(
            invocationID: validated.invocationID,
            senderID: validated.senderID,
            recipientID: validated.recipientID,
            capability: validated.capability,
            representation: validated.representation,
            arguments: OwnedBytes(copying: validated.arguments),
            executionBudget: budget
        )
    }
}
