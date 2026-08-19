public struct SymbioPeerClaim: Sendable, Codable, Hashable {
    public let transportPeerID: TransportPeerID
    public let descriptor: ParticipantDescriptor
    public let authentication: SymbioPeerAuthentication

    public init(
        transportPeerID: TransportPeerID,
        descriptor: ParticipantDescriptor,
        authentication: SymbioPeerAuthentication
    ) {
        self.transportPeerID = transportPeerID
        self.descriptor = descriptor
        self.authentication = authentication
    }
}
