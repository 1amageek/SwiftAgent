public enum SymbioRuntimeChange: Sendable {
    case joined(ParticipantView)
    case left(ParticipantID)
    case updated(ParticipantView)
    case becameAvailable(ParticipantID)
    case becameUnavailable(ParticipantID)
    case participantClaimRejected(TransportPeerID, reason: String)
    case invocationRejected(String, reason: String)
    case linkDiagnostic(String)
    case linkFailed(String)
}
