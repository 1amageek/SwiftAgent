public struct ParticipantClaimPin: Sendable, Hashable {
    public let participantID: ParticipantID
    public let authenticationMethod: String
    public let authenticationSubject: String

    public init(
        participantID: ParticipantID,
        authenticationMethod: String,
        authenticationSubject: String
    ) {
        self.participantID = participantID
        self.authenticationMethod = authenticationMethod
        self.authenticationSubject = authenticationSubject
    }
}
