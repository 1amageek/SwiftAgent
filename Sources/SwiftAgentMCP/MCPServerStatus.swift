/// A manager-level view combining connection, policy, and cleanup ownership.
public struct MCPServerStatus: Sendable {
    public let name: String
    public let isConnected: Bool
    public let isEnabled: Bool
    public let isTransitioning: Bool
    public let hasPendingCleanup: Bool

    public init(
        name: String,
        isConnected: Bool,
        isEnabled: Bool,
        isTransitioning: Bool,
        hasPendingCleanup: Bool
    ) {
        self.name = name
        self.isConnected = isConnected
        self.isEnabled = isEnabled
        self.isTransitioning = isTransitioning
        self.hasPendingCleanup = hasPendingCleanup
    }
}
