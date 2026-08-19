struct MCPClientLifecycleSnapshot: Sendable {
    let isConnected: Bool
    let requiresCleanup: Bool
}
