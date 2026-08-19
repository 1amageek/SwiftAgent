public struct ParticipantHandle: Sendable, Hashable {
    public let participantID: ParticipantID
    let registrationID: String

    init(participantID: ParticipantID, registrationID: String) {
        self.participantID = participantID
        self.registrationID = registrationID
    }
}
