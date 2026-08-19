public struct AggregateMember: Identifiable, Sendable, Codable, Hashable {
    public let id: ParticipantID
    public let weight: Double
    public let role: String?

    public init(id: ParticipantID, weight: Double = 1, role: String? = nil) {
        self.id = id
        self.weight = weight
        self.role = role
    }
}
