import Foundation
import Logging
import MCP
import SwiftAgent
import Testing
@testable import SwiftAgentMCP

@Suite("MCP server lifecycle")
struct MCPServerLifecycleTests {
    @Test("A terminal receive failure is surfaced by run", .timeLimit(.minutes(1)))
    func receiveFailureIsSurfaced() async {
        let transport = FailingReceiveTransport()
        let task = Task {
            try await EmptyMCPServer().run(transport: transport)
        }

        await transport.failReceive()

        do {
            try await task.value
            Issue.record("Expected the terminal transport failure")
        } catch let error as MCPServerError {
            guard case .transportFailure(operation: .receive, message: _) = error else {
                Issue.record("Unexpected MCP server error: \(error)")
                return
            }
        } catch {
            Issue.record("Unexpected error: \(error)")
        }
        #expect(await transport.disconnectCallCount == 1)
    }

    @Test("A clean transport EOF is surfaced by run", .timeLimit(.minutes(1)))
    func receiveEOFIsSurfaced() async {
        let transport = FailingReceiveTransport()
        let task = Task {
            try await EmptyMCPServer().run(transport: transport)
        }

        await transport.finishReceive()

        do {
            try await task.value
            Issue.record("Expected clean transport EOF to be terminal")
        } catch let error as MCPServerError {
            guard case .transportFailure(operation: .receive, message: _) = error else {
                Issue.record("Unexpected MCP server error: \(error)")
                return
            }
        } catch {
            Issue.record("Unexpected error: \(error)")
        }
        #expect(await transport.disconnectCallCount == 1)
    }

    @Test("An unexpected receive cancellation is surfaced by run", .timeLimit(.minutes(1)))
    func receiveCancellationIsSurfaced() async {
        let transport = FailingReceiveTransport()
        let task = Task {
            try await EmptyMCPServer().run(transport: transport)
        }

        await transport.cancelReceive()

        do {
            try await task.value
            Issue.record("Expected receive cancellation to be terminal")
        } catch let error as MCPServerError {
            guard case .transportFailure(operation: .receive, message: _) = error else {
                Issue.record("Unexpected MCP server error: \(error)")
                return
            }
        } catch {
            Issue.record("Unexpected error: \(error)")
        }
        #expect(await transport.disconnectCallCount == 1)
    }

    @Test("Shutdown cancels and drains owned tool invocations", .timeLimit(.minutes(1)))
    func shutdownDrainsInvocations() async throws {
        let probe = MCPInvocationProbe()
        let tool = try BlockingMCPServerTool(probe: probe)
        let registry = MCPServerInvocationRegistry()
        let task = Task {
            try await registry.call(tool: tool, arguments: nil)
        }

        #expect(await probe.waitUntilStarted())
        await registry.shutdown()

        await #expect(throws: CancellationError.self) {
            try await task.value
        }
        #expect(await probe.wasCancelled)
    }

    @Test("Tool invocation capacity rejects excess work", .timeLimit(.minutes(1)))
    func invocationCapacityIsBounded() async throws {
        let probe = MCPInvocationProbe()
        let tool = try BlockingMCPServerTool(probe: probe)
        let registry = MCPServerInvocationRegistry(
            maximumConcurrentInvocations: 1
        )
        let first = Task {
            try await registry.call(tool: tool, arguments: nil)
        }
        #expect(await probe.waitUntilStarted())

        await #expect(throws: MCPServerError.self) {
            _ = try await registry.call(tool: tool, arguments: nil)
        }
        await registry.shutdown()
        await #expect(throws: CancellationError.self) {
            _ = try await first.value
        }
    }

    @Test("Unexpected tool cancellation is a typed failure", .timeLimit(.minutes(1)))
    func unexpectedToolCancellationIsTypedFailure() async throws {
        let registry = MCPServerInvocationRegistry()
        let tool = try UnexpectedlyCancellingMCPServerTool()

        await #expect(throws: MCPServerError.self) {
            _ = try await registry.call(tool: tool, arguments: nil)
        }
        await registry.shutdown()
    }

    @Test("Server transport disconnect drains admitted sends", .timeLimit(.minutes(1)))
    func transportDisconnectDrainsSend() async throws {
        let transport = BlockingSendTransport()
        let monitor = MCPServerTransportMonitor(
            transport: transport,
            logger: await transport.logger
        )
        try await monitor.connect()
        let send = Task {
            try await monitor.send(Data("response".utf8))
        }
        #expect(await transport.waitUntilSendStarted())

        await monitor.disconnect()

        await #expect(throws: CancellationError.self) {
            try await send.value
        }
        #expect(await transport.sendFinished)
        #expect(await transport.disconnectCallCount == 1)
    }

    @Test("Server transport rejects oversized inbound messages", .timeLimit(.minutes(1)))
    func serverTransportRejectsOversizedInboundMessage() async throws {
        let transport = FailingReceiveTransport()
        let monitor = MCPServerTransportMonitor(
            transport: transport,
            maximumMessageBytes: 4,
            logger: await transport.logger
        )
        try await monitor.connect()
        let stream = await monitor.receive()
        var iterator = stream.makeAsyncIterator()
        await transport.emit(Data(repeating: 0, count: 5))

        await #expect(throws: MCPServerError.self) {
            _ = try await iterator.next()
        }
        #expect(await monitor.failure() != nil)
        await monitor.disconnect()
    }
}

private struct EmptyMCPServer: MCPServer {
    init() {}

    let tools: [any MCPServerTool] = []
}

private enum TestTransportError: Error {
    case receiveFailed
}

private actor FailingReceiveTransport: Transport {
    nonisolated let logger = Logger(label: "swift-agent.tests.mcp-server-transport")

    private let stream: AsyncThrowingStream<Data, Swift.Error>
    private let continuation: AsyncThrowingStream<Data, Swift.Error>.Continuation
    private(set) var disconnectCallCount = 0

    init() {
        let pair = AsyncThrowingStream<Data, Swift.Error>.makeStream()
        stream = pair.stream
        continuation = pair.continuation
    }

    func connect() async throws {}

    func disconnect() async {
        disconnectCallCount += 1
        continuation.finish()
    }

    func send(_ data: Data) async throws {}

    func receive() -> AsyncThrowingStream<Data, Swift.Error> {
        stream
    }

    func failReceive() {
        continuation.finish(throwing: TestTransportError.receiveFailed)
    }

    func finishReceive() {
        continuation.finish()
    }

    func cancelReceive() {
        continuation.finish(throwing: CancellationError())
    }

    func emit(_ data: Data) {
        continuation.yield(data)
    }
}

private actor BlockingSendTransport: Transport {
    nonisolated let logger = Logger(label: "swift-agent.tests.mcp-server-send")

    private let stream: AsyncThrowingStream<Data, Swift.Error>
    private let continuation: AsyncThrowingStream<Data, Swift.Error>.Continuation
    private var sendContinuation: CheckedContinuation<Void, any Error>?
    private var sendStarted = false
    private var sendStartWaiters: [CheckedContinuation<Void, Never>] = []
    private(set) var sendFinished = false
    private(set) var disconnectCallCount = 0

    init() {
        let pair = AsyncThrowingStream<Data, Swift.Error>.makeStream()
        stream = pair.stream
        continuation = pair.continuation
    }

    func connect() async throws {}

    func disconnect() async {
        disconnectCallCount += 1
        continuation.finish()
        let pending = sendContinuation
        sendContinuation = nil
        pending?.resume(throwing: CancellationError())
    }

    func send(_ data: Data) async throws {
        sendStarted = true
        let waiters = sendStartWaiters
        sendStartWaiters.removeAll()
        for waiter in waiters {
            waiter.resume()
        }
        do {
            try await withCheckedThrowingContinuation { continuation in
                sendContinuation = continuation
            }
        } catch {
            sendFinished = true
            throw error
        }
        sendFinished = true
    }

    func receive() -> AsyncThrowingStream<Data, Swift.Error> {
        stream
    }

    func waitUntilSendStarted() async -> Bool {
        if sendStarted {
            return true
        }
        await withCheckedContinuation { continuation in
            if sendStarted {
                continuation.resume()
            } else {
                sendStartWaiters.append(continuation)
            }
        }
        return sendStarted
    }
}

private struct BlockingMCPServerTool: MCPServerTool {
    let name = "blocking"
    let description = "Waits until the invocation is cancelled"
    let parameters: GenerationSchema

    private let probe: MCPInvocationProbe

    init(probe: MCPInvocationProbe) throws {
        self.probe = probe
        parameters = try GenerationSchema(
            root: DynamicGenerationSchema(
                name: "BlockingArguments",
                description: nil,
                properties: []
            ),
            dependencies: []
        )
    }

    func call(arguments: [String: MCP.Value]?) async throws -> CallTool.Result {
        await probe.markStarted()
        do {
            try await Task.sleep(for: .seconds(30))
        } catch is CancellationError {
            await probe.markCancelled()
            throw CancellationError()
        }
        return CallTool.Result(content: [])
    }
}

private struct UnexpectedlyCancellingMCPServerTool: MCPServerTool {
    let name = "unexpected-cancellation"
    let description = "Cancels without an ownership cancellation"
    let parameters: GenerationSchema

    init() throws {
        parameters = try GenerationSchema(
            root: DynamicGenerationSchema(
                name: "UnexpectedCancellationArguments",
                description: nil,
                properties: []
            ),
            dependencies: []
        )
    }

    func call(arguments: [String: MCP.Value]?) async throws -> CallTool.Result {
        throw CancellationError()
    }
}

private actor MCPInvocationProbe {
    private var started = false
    private(set) var wasCancelled = false

    func markStarted() {
        started = true
    }

    func markCancelled() {
        wasCancelled = true
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
}
