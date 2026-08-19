import MCP

actor MCPServerLifecycle {
    private let server: Server
    private let transport: MCPServerTransportMonitor
    private let invocations: MCPServerInvocationRegistry
    private var shutdownTask: Task<Void, Never>?

    init(
        server: Server,
        transport: MCPServerTransportMonitor,
        invocations: MCPServerInvocationRegistry
    ) {
        self.server = server
        self.transport = transport
        self.invocations = invocations
    }

    func shutdown() async {
        if let shutdownTask {
            await shutdownTask.value
            return
        }
        let server = self.server
        let transport = self.transport
        let invocations = self.invocations
        let task = Task {
            await transport.beginShutdown()
            await transport.disconnect()
            await server.stop()
            await invocations.shutdown()
        }
        shutdownTask = task
        await task.value
    }
}
