import SwiftAgentSymbio

public protocol Replicable: Sendable {
    func replicate() async throws -> ParticipantView
}
