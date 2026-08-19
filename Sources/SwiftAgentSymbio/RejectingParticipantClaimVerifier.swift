public struct RejectingParticipantClaimVerifier: ParticipantClaimVerifier {
    public init() {}

    public func verify(
        _ claim: SymbioPeerClaim
    ) async throws -> VerifiedParticipantBinding {
        throw SymbioRuntimeError.participantClaimRejected(
            peerID: claim.transportPeerID,
            reason: "No participant claim verifier is configured"
        )
    }
}
