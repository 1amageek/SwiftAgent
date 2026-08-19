import SwiftAgent

@Generable
public struct ReplicateArguments: Sendable {
    @Guide(description: "Reason this work requires another participant")
    public let reason: String
}
