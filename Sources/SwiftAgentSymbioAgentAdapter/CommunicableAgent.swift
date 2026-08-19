import Foundation
import SwiftAgent
import SwiftAgentSymbio

public protocol CommunicableAgent: Actor {
    nonisolated var participantID: ParticipantID { get }
    nonisolated var displayName: String? { get }
    nonisolated var perceptions: [any Perception] { get }

    func receive(_ data: Data, perception: String) async throws -> Data?
}

extension CommunicableAgent {
    public nonisolated var displayName: String? {
        nil
    }
}
