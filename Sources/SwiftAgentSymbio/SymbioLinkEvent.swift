public enum SymbioLinkEvent: Sendable {
    case peerConnected(TransportPeerID)
    case peerClaimed(SymbioPeerClaim)
    case participantWithdrawn(
        ParticipantID,
        from: TransportPeerID
    )
    case peerDisconnected(TransportPeerID)
    case invocationReceived(
        envelope: SymbioInvocationEnvelope,
        replyContext: SymbioReplyContext
    )
    case diagnostic(String)
}
