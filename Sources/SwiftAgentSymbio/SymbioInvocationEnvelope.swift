import Foundation
import NetworkingCore

public struct SymbioInvocationEnvelope: Sendable, Hashable {
    public let invocationID: String
    public let senderID: ParticipantID
    public let recipientID: ParticipantID
    public let capability: String
    public let representation: MessageRepresentation
    public let arguments: OwnedBytes
    public let executionBudget: Duration

    public init(
        invocationID: String = UUID().uuidString,
        senderID: ParticipantID,
        recipientID: ParticipantID,
        capability: String,
        representation: MessageRepresentation,
        arguments: OwnedBytes,
        executionBudget: Duration
    ) {
        self.invocationID = invocationID
        self.senderID = senderID
        self.recipientID = recipientID
        self.capability = capability
        self.representation = representation
        self.arguments = arguments
        self.executionBudget = executionBudget
    }
}
