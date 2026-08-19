import Foundation
import Testing
@testable import SwiftAgentMCP

@Suite("MCP deadline ownership")
struct MCPDeadlineTests {
    private enum TestError: Error {
        case timedOut
    }

    @Test("Timeout cleanup finishes before the deadline returns", .timeLimit(.minutes(1)))
    func timeoutCleanupIsDrained() async {
        let probe = MCPDeadlineProbe()

        await #expect(throws: TestError.self) {
            _ = try await withMCPDeadline(
                .milliseconds(1),
                timeoutError: { TestError.timedOut },
                onCancellation: { reason in
                    if case .timedOut = reason {
                        await probe.release()
                    }
                },
                operation: {
                    await probe.markStarted()
                    await probe.waitForRelease()
                    await probe.markOperationFinished()
                    return 1
                }
            )
        }

        #expect(await probe.operationFinished)
    }

    @Test("Caller cancellation runs cleanup and drains the operation", .timeLimit(.minutes(1)))
    func callerCancellationIsDrained() async {
        let probe = MCPDeadlineProbe()
        let task = Task {
            try await withMCPDeadline(
                .seconds(30),
                timeoutError: { TestError.timedOut },
                onCancellation: { reason in
                    if case .callerCancelled = reason {
                        await probe.release()
                    }
                },
                operation: {
                    await probe.markStarted()
                    await probe.waitForRelease()
                    await probe.markOperationFinished()
                    return 1
                }
            )
        }
        #expect(await probe.waitUntilStarted())

        task.cancel()

        await #expect(throws: CancellationError.self) {
            try await task.value
        }
        #expect(await probe.operationFinished)
    }
}

private actor MCPDeadlineProbe {
    private var started = false
    private var released = false
    private var releaseWaiter: CheckedContinuation<Void, Never>?
    private(set) var operationFinished = false

    func markStarted() {
        started = true
    }

    func waitUntilStarted() async -> Bool {
        for _ in 0..<100 {
            if started {
                return true
            }
            await Task.yield()
        }
        return started
    }

    func waitForRelease() async {
        if released {
            return
        }
        await withCheckedContinuation { continuation in
            if released {
                continuation.resume()
            } else {
                releaseWaiter = continuation
            }
        }
    }

    func release() {
        guard !released else {
            return
        }
        released = true
        let waiter = releaseWaiter
        releaseWaiter = nil
        waiter?.resume()
    }

    func markOperationFinished() {
        operationFinished = true
    }
}
