import Foundation
import SwiftAgentSymbio

struct SymbioWireAnnouncement: Codable, Sendable {
    enum Operation: String, Codable, Sendable {
        case publish
        case withdraw
    }

    let operation: Operation
    let descriptor: ParticipantDescriptor?
    let participantID: ParticipantID?

    static func publish(_ descriptor: ParticipantDescriptor) -> Self {
        Self(
            operation: .publish,
            descriptor: descriptor,
            participantID: nil
        )
    }

    static func withdraw(_ participantID: ParticipantID) -> Self {
        Self(
            operation: .withdraw,
            descriptor: nil,
            participantID: participantID
        )
    }

    func validated() throws -> Self {
        switch operation {
        case .publish:
            guard let descriptor, participantID == nil else {
                throw PeerConnectivitySymbioError.invalidWireMessage(
                    "Publish announcement must contain only a descriptor"
                )
            }
            guard !descriptor.id.rawValue.trimmingCharacters(
                in: .whitespacesAndNewlines
            ).isEmpty else {
                throw PeerConnectivitySymbioError.invalidWireMessage(
                    "Published participant ID must not be empty"
                )
            }
        case .withdraw:
            guard descriptor == nil, let participantID else {
                throw PeerConnectivitySymbioError.invalidWireMessage(
                    "Withdraw announcement must contain only a participant ID"
                )
            }
            guard !participantID.rawValue.trimmingCharacters(
                in: .whitespacesAndNewlines
            ).isEmpty else {
                throw PeerConnectivitySymbioError.invalidWireMessage(
                    "Withdraw participant ID must not be empty"
                )
            }
        }
        return self
    }
}
