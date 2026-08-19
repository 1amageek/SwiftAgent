import SwiftAgent
import SwiftAgentSymbio

public struct ReplicateTool: Tool, Sendable {
    public typealias Arguments = ReplicateArguments
    public typealias Output = ReplicateOutput

    public static let name = "replicate_agent"
    public var name: String { Self.name }

    public static let toolDescription = """
        Create and register another participant for independently executable work.

        Use this capability when the current task contains independent work that
        can be assigned concurrently. The returned participant identifier can be
        used with the Symbio runtime after registration succeeds.
        """

    public var description: String { Self.toolDescription }
    public var parameters: GenerationSchema { ReplicateArguments.generationSchema }

    private let replicator: any Replicable

    public init(replicator: any Replicable) {
        self.replicator = replicator
    }

    public func call(arguments: ReplicateArguments) async throws -> ReplicateOutput {
        let participant = try await replicator.replicate()
        return ReplicateOutput(
            participantID: participant.id.rawValue,
            affordances: participant.affordances.map(\.contract.id).sorted(),
            reason: arguments.reason
        )
    }
}
