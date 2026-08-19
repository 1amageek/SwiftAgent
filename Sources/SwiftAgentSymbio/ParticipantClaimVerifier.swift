public protocol ParticipantClaimVerifier: Sendable {
    /// Verifies one transport-bound claim. Implementations must observe task
    /// cancellation so runtime shutdown can drain verification ownership. The
    /// returned descriptor may be a verifier-canonicalized descriptor, but its
    /// participant and transport peer identities cannot change.
    func verify(_ claim: SymbioPeerClaim) async throws -> VerifiedParticipantBinding
}
