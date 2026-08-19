import Testing
@testable import SwiftAgentMCP

@Suite("MCP process ownership")
struct MCPProcessLeaseTests {
    @Test("Concurrent shutdown callers share one cleanup", .timeLimit(.minutes(1)))
    func concurrentShutdownIsCoalesced() async throws {
        let launched = try MCPProcessLease.launch(
            serverName: "test",
            command: "/bin/cat",
            arguments: [],
            environment: nil,
            workingDirectory: nil
        )

        async let first: Void = launched.lease.shutdown()
        async let second: Void = launched.lease.shutdown()
        try await first
        try await second
    }

    @Test("Caller cancellation does not abandon process cleanup", .timeLimit(.minutes(1)))
    func cancelledCallerStillDrainsCleanup() async throws {
        let launched = try MCPProcessLease.launch(
            serverName: "test",
            command: "/bin/cat",
            arguments: [],
            environment: nil,
            workingDirectory: nil
        )
        let shutdown = Task {
            try await launched.lease.shutdown()
        }
        shutdown.cancel()

        try await shutdown.value
        try await launched.lease.shutdown()
    }
}
