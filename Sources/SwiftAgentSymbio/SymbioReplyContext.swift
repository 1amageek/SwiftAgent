public struct SymbioReplyContext: Sendable, Hashable {
    /// A link-issued, single-use identifier unique for the link lifetime.
    public let id: String
    public let transportPeerID: TransportPeerID

    public init(id: String, transportPeerID: TransportPeerID) {
        self.id = id
        self.transportPeerID = transportPeerID
    }
}
