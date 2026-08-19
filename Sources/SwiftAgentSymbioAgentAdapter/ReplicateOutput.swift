import SwiftAgent

public struct ReplicateOutput: Sendable {
    public let participantID: String
    public let affordances: [String]
    public let reason: String

    public init(
        participantID: String,
        affordances: [String],
        reason: String
    ) {
        self.participantID = participantID
        self.affordances = affordances
        self.reason = reason
    }
}

extension ReplicateOutput: PromptRepresentable {
    public var promptRepresentation: Prompt {
        Prompt("""
            Participant registered:
            - Participant ID: \(participantID)
            - Affordances: \(affordances.joined(separator: ", "))
            - Reason: \(reason)
            """)
    }
}
