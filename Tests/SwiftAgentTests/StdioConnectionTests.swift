import Foundation
import Testing
@testable import SwiftAgent

@Suite("Stdio connection ownership")
struct StdioConnectionTests {
    @Test("Approval input uses the connection-owned stdin reader", .timeLimit(.minutes(1)))
    func approvalUsesConnectionReader() async throws {
        let input = Pipe()
        let output = Pipe()
        let errorOutput = Pipe()
        let connection = StdioConnection(
            input: input.fileHandleForReading,
            output: output.fileHandleForWriting,
            errorOutput: errorOutput.fileHandleForWriting,
            prompt: "> ",
            verbose: false
        )
        let handler = StdioApprovalHandler(connection: connection)
        let approval = Task {
            try await handler.requestApproval(
                PermissionRequest(
                    toolName: "Read",
                    toolInput: ["path": "/tmp/input"]
                ),
                approvalID: "approval-1"
            )
        }

        try input.fileHandleForWriting.write(contentsOf: Data("y\n".utf8))
        let response = try await approval.value
        switch response {
        case .allowOnce:
            break
        case .alwaysAllow, .deny, .denyAndBlock:
            Issue.record("Expected allow-once approval")
        }

        try await connection.shutdown()
        try input.fileHandleForWriting.close()
        try output.fileHandleForWriting.close()
        try errorOutput.fileHandleForWriting.close()
    }

    @Test("Approval EOF is reported as a connection failure", .timeLimit(.minutes(1)))
    func approvalEOFFailsExplicitly() async throws {
        let input = Pipe()
        let output = Pipe()
        let errorOutput = Pipe()
        let connection = StdioConnection(
            input: input.fileHandleForReading,
            output: output.fileHandleForWriting,
            errorOutput: errorOutput.fileHandleForWriting,
            prompt: "> ",
            verbose: false
        )
        let handler = StdioApprovalHandler(connection: connection)
        try input.fileHandleForWriting.close()

        do {
            _ = try await handler.requestApproval(
                PermissionRequest(
                    toolName: "Read",
                    toolInput: ["path": "/tmp/input"]
                ),
                approvalID: "approval-eof"
            )
            Issue.record("Expected approval EOF to fail")
        } catch let error as AgentConnectionError {
            guard case .inputClosed = error else {
                Issue.record("Unexpected connection error: \(error)")
                return
            }
        } catch {
            Issue.record("Unexpected error: \(error)")
        }

        try await connection.shutdown()
        try output.fileHandleForWriting.close()
        try errorOutput.fileHandleForWriting.close()
    }

    @Test("Cancelling a stdin waiter releases it", .timeLimit(.minutes(1)))
    func cancelledWaiterIsReleased() async throws {
        let input = Pipe()
        let source = StdioLineSource(input: input.fileHandleForReading)
        let read = Task {
            try await source.next()
        }
        await Task.yield()
        read.cancel()

        await #expect(throws: CancellationError.self) {
            _ = try await read.value
        }

        try await source.shutdown()
        try input.fileHandleForWriting.close()
    }

    @Test("Cancelling a waiter preserves the next line", .timeLimit(.minutes(1)))
    func cancelledWaiterDoesNotConsumeNextLine() async throws {
        let buffer = StdioLineBuffer(capacity: 1)
        let cancelledRead = Task {
            try await buffer.next()
        }
        await Task.yield()

        cancelledRead.cancel()
        await #expect(throws: CancellationError.self) {
            _ = try await cancelledRead.value
        }

        #expect(buffer.enqueue("preserved"))
        let preservedLine = try await buffer.next()
        #expect(preservedLine == "preserved")
        buffer.finish()
    }

    @Test("Concurrent connection shutdown shares input cleanup", .timeLimit(.minutes(1)))
    func concurrentShutdownIsCoalesced() async throws {
        let input = Pipe()
        let output = Pipe()
        let errorOutput = Pipe()
        let connection = StdioConnection(
            input: input.fileHandleForReading,
            output: output.fileHandleForWriting,
            errorOutput: errorOutput.fileHandleForWriting,
            prompt: "> ",
            verbose: false
        )

        async let first: Void = connection.shutdown()
        async let second: Void = connection.shutdown()
        try await first
        try await second

        try input.fileHandleForWriting.close()
        try output.fileHandleForWriting.close()
        try errorOutput.fileHandleForWriting.close()
    }
}
