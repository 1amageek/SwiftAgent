import Foundation
import Logging
import MCP
import Testing
@testable import SwiftAgentMCP

@Suite("MCP client transport ownership")
struct MCPClientTransportOwnerTests {
    @Test("Receive EOF is terminal and cannot busy-loop", .timeLimit(.minutes(1)))
    func receiveEOFIsTerminal() async throws {
        let transport = OwnerTestTransport()
        let owner = MCPClientTransportOwner(
            serverName: "test",
            transport: transport,
            logger: await transport.logger
        )
        try await owner.connect()
        let stream = await owner.receive()
        await transport.finishReceive()
        var iterator = stream.makeAsyncIterator()

        await #expect(throws: MCPClientError.self) {
            _ = try await iterator.next()
        }
        #expect(await owner.operationalFailure() != nil)

        let repeatedStream = await owner.receive()
        var repeatedIterator = repeatedStream.makeAsyncIterator()
        await #expect(throws: MCPClientError.self) {
            _ = try await repeatedIterator.next()
        }
        await owner.disconnect()
        #expect(await transport.disconnectCallCount == 1)
    }

    @Test("Unexpected receive cancellation is terminal", .timeLimit(.minutes(1)))
    func unexpectedReceiveCancellationIsTerminal() async throws {
        let transport = OwnerTestTransport()
        let owner = MCPClientTransportOwner(
            serverName: "test",
            transport: transport,
            logger: await transport.logger
        )
        try await owner.connect()
        let stream = await owner.receive()
        await transport.cancelReceive()
        var iterator = stream.makeAsyncIterator()

        await #expect(throws: MCPClientError.self) {
            _ = try await iterator.next()
        }
        #expect(await owner.operationalFailure() != nil)
        await owner.disconnect()
        #expect(await transport.disconnectCallCount == 1)
    }

    @Test("Disconnect drains an admitted send", .timeLimit(.minutes(1)))
    func disconnectDrainsSend() async throws {
        let transport = OwnerTestTransport(blocksSend: true)
        let owner = MCPClientTransportOwner(
            serverName: "test",
            transport: transport,
            logger: await transport.logger
        )
        try await owner.connect()
        let send = Task {
            try await owner.send(Data("request".utf8))
        }
        #expect(await transport.waitUntilSendStarted())

        await owner.disconnect()

        await #expect(throws: CancellationError.self) {
            try await send.value
        }
        #expect(await transport.sendFinished)
        #expect(await transport.disconnectCallCount == 1)
    }

    @Test("Caller cancellation does not abandon disconnect", .timeLimit(.minutes(1)))
    func callerCancellationDoesNotAbandonDisconnect() async throws {
        let transport = OwnerTestTransport(blocksDisconnect: true)
        let owner = MCPClientTransportOwner(
            serverName: "test",
            transport: transport,
            logger: await transport.logger
        )
        try await owner.connect()

        let disconnect = Task {
            await owner.disconnect()
        }
        #expect(await transport.waitUntilDisconnectStarted())
        disconnect.cancel()
        await transport.releaseDisconnect()
        await disconnect.value

        #expect(await transport.disconnectFinished)
        #expect(await transport.disconnectCallCount == 1)
        let observedCancellation = await transport.disconnectObservedCancellation
        #expect(!observedCancellation)
    }

    @Test("Oversized inbound messages terminate the connection", .timeLimit(.minutes(1)))
    func oversizedInboundMessageTerminatesConnection() async throws {
        let transport = OwnerTestTransport()
        let owner = MCPClientTransportOwner(
            serverName: "test",
            transport: transport,
            maximumMessageBytes: 4,
            logger: await transport.logger
        )
        try await owner.connect()
        let stream = await owner.receive()
        var iterator = stream.makeAsyncIterator()
        await transport.emit(Data(repeating: 0, count: 5))

        await #expect(throws: MCPClientError.self) {
            _ = try await iterator.next()
        }
        #expect(await owner.operationalFailure() != nil)
        await owner.disconnect()
    }

    @Test("Oversized outbound messages never reach the transport", .timeLimit(.minutes(1)))
    func oversizedOutboundMessageIsRejected() async throws {
        let transport = OwnerTestTransport()
        let owner = MCPClientTransportOwner(
            serverName: "test",
            transport: transport,
            maximumMessageBytes: 4,
            logger: await transport.logger
        )
        try await owner.connect()

        await #expect(throws: MCPClientError.self) {
            try await owner.send(Data(repeating: 0, count: 5))
        }
        #expect(await transport.sendCallCount == 0)
        await owner.disconnect()
    }
}

private actor OwnerTestTransport: Transport {
    nonisolated let logger = Logger(label: "swift-agent.tests.mcp-client-transport")

    private let stream: AsyncThrowingStream<Data, Swift.Error>
    private let continuation: AsyncThrowingStream<Data, Swift.Error>.Continuation
    private let blocksSend: Bool
    private let blocksDisconnect: Bool
    private var sendContinuation: CheckedContinuation<Void, any Error>?
    private var sendStarted = false
    private var sendStartWaiters: [CheckedContinuation<Void, Never>] = []
    private(set) var sendFinished = false
    private(set) var sendCallCount = 0
    private var disconnectContinuation: CheckedContinuation<Void, Never>?
    private var disconnectStarted = false
    private var disconnectStartWaiters: [CheckedContinuation<Void, Never>] = []
    private(set) var disconnectFinished = false
    private(set) var disconnectObservedCancellation = false
    private(set) var disconnectCallCount = 0

    init(blocksSend: Bool = false, blocksDisconnect: Bool = false) {
        let pair = AsyncThrowingStream<Data, Swift.Error>.makeStream()
        stream = pair.stream
        continuation = pair.continuation
        self.blocksSend = blocksSend
        self.blocksDisconnect = blocksDisconnect
    }

    func connect() async throws {}

    func disconnect() async {
        disconnectCallCount += 1
        disconnectStarted = true
        let waiters = disconnectStartWaiters
        disconnectStartWaiters.removeAll()
        for waiter in waiters {
            waiter.resume()
        }
        if blocksDisconnect {
            await withCheckedContinuation { continuation in
                disconnectContinuation = continuation
            }
        }
        disconnectObservedCancellation = Task.isCancelled
        continuation.finish()
        let pending = sendContinuation
        sendContinuation = nil
        pending?.resume(throwing: CancellationError())
        disconnectFinished = true
    }

    func send(_ data: Data) async throws {
        sendCallCount += 1
        sendStarted = true
        let waiters = sendStartWaiters
        sendStartWaiters.removeAll()
        for waiter in waiters {
            waiter.resume()
        }
        if blocksSend {
            do {
                try await withCheckedThrowingContinuation { continuation in
                    sendContinuation = continuation
                }
            } catch {
                sendFinished = true
                throw error
            }
        }
        sendFinished = true
    }

    func receive() -> AsyncThrowingStream<Data, Swift.Error> {
        stream
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

    func waitUntilDisconnectStarted() async -> Bool {
        if disconnectStarted {
            return true
        }
        await withCheckedContinuation { continuation in
            if disconnectStarted {
                continuation.resume()
            } else {
                disconnectStartWaiters.append(continuation)
            }
        }
        return disconnectStarted
    }

    func releaseDisconnect() {
        let continuation = disconnectContinuation
        disconnectContinuation = nil
        continuation?.resume()
    }
}
