public struct PinnedParticipantClaimVerifier: ParticipantClaimVerifier {
    private let pinsByPeerID: [TransportPeerID: Set<ParticipantClaimPin>]

    public init(
        pinsByPeerID: [TransportPeerID: Set<ParticipantClaimPin>]
    ) {
        self.pinsByPeerID = pinsByPeerID
    }

    public func verify(
        _ claim: SymbioPeerClaim
    ) async throws -> VerifiedParticipantBinding {
        guard let peerPins = pinsByPeerID[claim.transportPeerID] else {
            throw SymbioRuntimeError.participantClaimRejected(
                peerID: claim.transportPeerID,
                reason: "The transport peer is not pinned"
            )
        }
        let matchingPins = peerPins.filter {
            $0.participantID == claim.descriptor.id
        }
        guard !matchingPins.isEmpty else {
            throw SymbioRuntimeError.participantClaimRejected(
                peerID: claim.transportPeerID,
                reason: "The claimed participant is not pinned for this transport peer"
            )
        }
        guard matchingPins.contains(where: {
            $0.authenticationMethod == claim.authentication.method
        }) else {
            throw SymbioRuntimeError.participantClaimRejected(
                peerID: claim.transportPeerID,
                reason: "The authentication method does not match the pin"
            )
        }
        guard matchingPins.contains(where: {
            $0.authenticationMethod == claim.authentication.method
                && $0.authenticationSubject == claim.authentication.subject
        }) else {
            throw SymbioRuntimeError.participantClaimRejected(
                peerID: claim.transportPeerID,
                reason: "The authenticated subject does not match the pin"
            )
        }
        return VerifiedParticipantBinding(
            transportPeerID: claim.transportPeerID,
            descriptor: claim.descriptor,
            verificationMethod: "pinned-transport-identity"
        )
    }
}
