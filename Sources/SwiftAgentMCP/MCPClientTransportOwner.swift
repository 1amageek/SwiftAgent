import Foundation
import Logging
import MCP

/// Owns the SDK transport loop and drains every send before disconnect returns.
actor MCPClientTransportOwner: Transport {
    private enum State {
        case idle
        case connecting
        case running
        case stopping
        case finished
    }

    nonisolated let logger: Logger

    private let serverName: String
    private let transport: any Transport
    private let maximumMessageBytes: Int
    private var state = State.idle
    private var receiveTask: Task<Void, Never>?
    private var receiveWasRequested = false
    private var terminalFailure: MCPClientError?
    private var activeSendCount = 0
    private var sendDrainWaiters: [CheckedContinuation<Void, Never>] = []
    private var disconnectTask: Task<Void, Never>?
    private var transportDisconnectTask: Task<Void, Never>?
    private var transportDisconnected = false

    init(
        serverName: String,
        transport: any Transport,
        maximumMessageBytes: Int = 4 * 1_024 * 1_024,
        logger: Logger
    ) {
        self.serverName = serverName
        self.transport = transport
        self.maximumMessageBytes = maximumMessageBytes
        self.logger = logger
    }

    func connect() async throws {
        guard case .idle = state else {
            throw lifecycleError("The transport can only be connected once")
        }
        state = .connecting
        do {
            try await transport.connect()
            guard case .connecting = state else {
                throw lifecycleError(
                    "The transport was disconnected while connecting"
                )
            }
            state = .running
        } catch {
            if case .connecting = state {
                state = .idle
            }
            throw error
        }
    }

    func disconnect() async {
        if let disconnectTask {
            await disconnectTask.value
            return
        }
        if case .finished = state {
            return
        }
        state = .stopping
        let receiveTask = self.receiveTask
        self.receiveTask = nil
        let disconnect = Task { [self] in
            receiveTask?.cancel()
            await disconnectUnderlyingTransport()
            await receiveTask?.value
            await waitForSendDrain()
            finishDisconnect()
        }
        disconnectTask = disconnect
        await disconnect.value
    }

    func send(_ data: Data) async throws {
        guard case .running = state, terminalFailure == nil else {
            throw terminalFailure ?? lifecycleError(
                "The transport is not accepting sends"
            )
        }
        guard data.count <= maximumMessageBytes else {
            throw MCPClientError.messageTooLarge(
                server: serverName,
                direction: "outbound",
                actual: data.count,
                maximum: maximumMessageBytes
            )
        }
        activeSendCount += 1
        defer { finishSend() }

        do {
            try await transport.send(data)
        } catch {
            recordTerminalFailure(
                "Transport send failed: \(error.localizedDescription)"
            )
            throw error
        }
    }

    func receive() -> AsyncThrowingStream<Data, Swift.Error> {
        let pair = AsyncThrowingStream<Data, Swift.Error>.makeStream(
            bufferingPolicy: .bufferingOldest(256)
        )
        guard case .running = state, terminalFailure == nil else {
            pair.continuation.finish(throwing: terminalFailure ?? lifecycleError(
                "The transport is not accepting a receiver"
            ))
            return pair.stream
        }
        guard !receiveWasRequested else {
            let error = lifecycleError(
                "The SDK requested the receive stream more than once"
            )
            recordTerminalFailure(error)
            pair.continuation.finish(throwing: error)
            return pair.stream
        }
        receiveWasRequested = true

        let transport = self.transport
        let maximumMessageBytes = self.maximumMessageBytes
        let serverName = self.serverName
        let task = Task {
            do {
                let source = await transport.receive()
                for try await data in source {
                    try Task.checkCancellation()
                    guard data.count <= maximumMessageBytes else {
                        let error = MCPClientError.messageTooLarge(
                            server: serverName,
                            direction: "inbound",
                            actual: data.count,
                            maximum: maximumMessageBytes
                        )
                        await self.recordTerminalFailure(error)
                        pair.continuation.finish(throwing: error)
                        await self.disconnectUnderlyingTransport()
                        return
                    }
                    switch pair.continuation.yield(data) {
                    case .enqueued:
                        continue
                    case .dropped:
                        let error = await self.lifecycleError(
                            "The bounded receive buffer overflowed"
                        )
                        await self.recordTerminalFailure(error)
                        pair.continuation.finish(throwing: error)
                        await self.disconnectUnderlyingTransport()
                        return
                    case .terminated:
                        await self.recordUnexpectedReceiveEnd(
                            "The receive consumer terminated"
                        )
                        await self.disconnectUnderlyingTransport()
                        return
                    @unknown default:
                        let error = await self.lifecycleError(
                            "The receive buffer returned an unknown state"
                        )
                        await self.recordTerminalFailure(error)
                        pair.continuation.finish(throwing: error)
                        await self.disconnectUnderlyingTransport()
                        return
                    }
                }
                if let failure = await self.recordUnexpectedReceiveEnd(
                    "The receive stream reached EOF"
                ) {
                    pair.continuation.finish(throwing: failure)
                } else {
                    pair.continuation.finish()
                }
            } catch is CancellationError {
                if let failure = await self.recordUnexpectedReceiveEnd(
                    "The receive stream was cancelled"
                ) {
                    pair.continuation.finish(throwing: failure)
                } else {
                    pair.continuation.finish()
                }
            } catch {
                await self.recordTerminalFailure(
                    "Transport receive failed: \(error.localizedDescription)"
                )
                pair.continuation.finish(throwing: error)
            }
        }
        receiveTask = task
        pair.continuation.onTermination = { @Sendable _ in
            task.cancel()
        }
        return pair.stream
    }

    func operationalFailure() -> MCPClientError? {
        guard case .running = state else {
            return terminalFailure ?? lifecycleError(
                "The transport is not running"
            )
        }
        return terminalFailure
    }

    private func recordUnexpectedReceiveEnd(_ reason: String) -> MCPClientError? {
        guard case .running = state else {
            return nil
        }
        recordTerminalFailure(reason)
        return terminalFailure
    }

    private func recordTerminalFailure(_ reason: String) {
        recordTerminalFailure(lifecycleError(reason))
    }

    private func recordTerminalFailure(_ error: MCPClientError) {
        guard terminalFailure == nil else {
            return
        }
        terminalFailure = error
    }

    private func finishSend() {
        activeSendCount -= 1
        guard activeSendCount == 0 else {
            return
        }
        let waiters = sendDrainWaiters
        sendDrainWaiters.removeAll()
        for waiter in waiters {
            waiter.resume()
        }
    }

    private func waitForSendDrain() async {
        guard activeSendCount > 0 else {
            return
        }
        await withCheckedContinuation { continuation in
            sendDrainWaiters.append(continuation)
        }
    }

    private func disconnectUnderlyingTransport() async {
        if let transportDisconnectTask {
            await transportDisconnectTask.value
            return
        }
        guard !transportDisconnected else {
            return
        }
        let transport = self.transport
        let task = Task {
            await transport.disconnect()
        }
        transportDisconnectTask = task
        await task.value
        transportDisconnectTask = nil
        transportDisconnected = true
    }

    private func finishDisconnect() {
        state = .finished
        disconnectTask = nil
    }

    private func lifecycleError(_ reason: String) -> MCPClientError {
        .transportTerminated(server: serverName, reason: reason)
    }
}
