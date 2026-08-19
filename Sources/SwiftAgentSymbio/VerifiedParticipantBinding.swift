public struct VerifiedParticipantBinding: Sendable, Codable, Hashable {
    public let transportPeerID: TransportPeerID
    public let descriptor: ParticipantDescriptor
    public let verificationMethod: String

    public init(
        transportPeerID: TransportPeerID,
        descriptor: ParticipantDescriptor,
        verificationMethod: String
    ) {
        self.transportPeerID = transportPeerID
        self.descriptor = descriptor
        self.verificationMethod = verificationMethod
    }
}
