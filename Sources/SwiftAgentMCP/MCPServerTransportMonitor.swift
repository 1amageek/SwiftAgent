import Foundation
import Logging
import MCP

/// Converts terminal transport failures hidden by the upstream server loop into
/// an explicit failure that `MCPServer.run(transport:)` can report.
actor MCPServerTransportMonitor: Transport {
    private static let receiveCapacity = 256

    nonisolated let logger: Logger

    private let transport: any Transport
    private let maximumMessageBytes: Int
    private var forwardingTask: Task<Void, Never>?
    private var terminalFailure: MCPServerError?
    private var isShuttingDown = false
    private var isConnecting = false
    private var isConnected = false
    private var isDisconnected = false
    private var disconnectTask: Task<Void, Never>?
    private var transportDisconnectTask: Task<Void, Never>?
    private var transportDisconnected = false
    private var activeSendCount = 0
    private var sendDrainWaiters: [CheckedContinuation<Void, Never>] = []

    init(
        transport: any Transport,
        maximumMessageBytes: Int = 4 * 1_024 * 1_024,
        logger: Logger
    ) {
        self.transport = transport
        self.maximumMessageBytes = maximumMessageBytes
        self.logger = logger
    }

    func connect() async throws {
        guard !isConnecting, !isConnected, !isShuttingDown,
              !isDisconnected else {
            throw MCPServerError.transportFailure(
                operation: .connect,
                message: "The monitored transport cannot be connected in its current state"
            )
        }
        isConnecting = true
        do {
            try await transport.connect()
            guard !isShuttingDown, !isDisconnected else {
                await disconnectUnderlyingTransport()
                throw MCPServerError.transportFailure(
                    operation: .connect,
                    message: "The monitored transport was disconnected while connecting"
                )
            }
            isConnecting = false
            isConnected = true
        } catch {
            isConnecting = false
            let failure = error as? MCPServerError
                ?? MCPServerError.transportFailure(
                    operation: .connect,
                    message: error.localizedDescription
                )
            recordFailure(failure)
            throw failure
        }
    }

    func disconnect() async {
        if let disconnectTask {
            await disconnectTask.value
            return
        }
        guard !isDisconnected else {
            return
        }
        isShuttingDown = true
        let task = forwardingTask
        forwardingTask = nil
        let disconnect = Task { [self] in
            task?.cancel()
            await disconnectUnderlyingTransport()
            await task?.value
            await waitForSendDrain()
            finishDisconnect()
        }
        disconnectTask = disconnect
        await disconnect.value
    }

    func send(_ data: Data) async throws {
        guard isConnected, !isShuttingDown, !isDisconnected,
              terminalFailure == nil else {
            throw terminalFailure ?? MCPServerError.transportFailure(
                operation: .send,
                message: "The monitored transport is not accepting sends"
            )
        }
        guard data.count <= maximumMessageBytes else {
            throw MCPServerError.transportFailure(
                operation: .send,
                message: "Outbound message is \(data.count) bytes, exceeding the \(maximumMessageBytes)-byte limit"
            )
        }
        activeSendCount += 1
        defer { finishSend() }
        do {
            try await transport.send(data)
        } catch {
            if !isShuttingDown {
                recordFailure(operation: .send, error: error)
                forwardingTask?.cancel()
                await disconnectUnderlyingTransport()
            }
            throw error
        }
    }

    func receive() -> AsyncThrowingStream<Data, Swift.Error> {
        let (stream, continuation) = AsyncThrowingStream<Data, Swift.Error>.makeStream(
            bufferingPolicy: .bufferingOldest(Self.receiveCapacity)
        )

        guard isConnected, !isShuttingDown, !isDisconnected,
              terminalFailure == nil else {
            continuation.finish(throwing: terminalFailure ?? MCPServerError.transportFailure(
                operation: .receive,
                message: "The monitored transport is not accepting a receiver"
            ))
            return stream
        }

        guard forwardingTask == nil else {
            let failure = MCPServerError.transportFailure(
                operation: .receive,
                message: "The receive stream was requested more than once"
            )
            terminalFailure = terminalFailure ?? failure
            continuation.finish(throwing: failure)
            return stream
        }

        let maximumMessageBytes = self.maximumMessageBytes
        let task = Task { [transport] in
            do {
                let source = await transport.receive()
                for try await data in source {
                    try Task.checkCancellation()
                    guard data.count <= maximumMessageBytes else {
                        let failure = MCPServerError.transportFailure(
                            operation: .receive,
                            message: "Inbound message is \(data.count) bytes, exceeding the \(maximumMessageBytes)-byte limit"
                        )
                        await self.recordFailure(failure)
                        continuation.finish(throwing: failure)
                        await self.disconnectUnderlyingTransport()
                        return
                    }
                    switch continuation.yield(data) {
                    case .enqueued:
                        continue
                    case .dropped:
                        let failure = MCPServerError.transportFailure(
                            operation: .receive,
                            message: "The bounded receive buffer exceeded its capacity of \(Self.receiveCapacity)"
                        )
                        await self.recordFailure(failure)
                        continuation.finish(throwing: failure)
                        await self.disconnectUnderlyingTransport()
                        return
                    case .terminated:
                        _ = await self.recordUnexpectedReceiveEnd(
                            "The server receive consumer terminated"
                        )
                        await self.disconnectUnderlyingTransport()
                        return
                    @unknown default:
                        let failure = MCPServerError.transportFailure(
                            operation: .receive,
                            message: "The bounded receive buffer returned an unknown state"
                        )
                        await self.recordFailure(failure)
                        continuation.finish(throwing: failure)
                        await self.disconnectUnderlyingTransport()
                        return
                    }
                }
                if let failure = await self.recordUnexpectedReceiveEnd(
                    "The transport receive stream reached EOF"
                ) {
                    continuation.finish(throwing: failure)
                } else {
                    continuation.finish()
                }
            } catch is CancellationError {
                if let failure = await self.recordUnexpectedReceiveEnd(
                    "The server receive consumer was cancelled"
                ) {
                    continuation.finish(throwing: failure)
                } else {
                    continuation.finish()
                }
            } catch {
                await self.recordFailure(operation: .receive, error: error)
                continuation.finish(throwing: error)
            }
        }
        forwardingTask = task
        continuation.onTermination = { @Sendable _ in
            task.cancel()
        }
        return stream
    }

    func beginShutdown() {
        isShuttingDown = true
    }

    func failure() -> MCPServerError? {
        terminalFailure
    }

    private func recordFailure(
        operation: MCPServerTransportOperation,
        error: any Error
    ) {
        recordFailure(MCPServerError.transportFailure(
            operation: operation,
            message: error.localizedDescription
        ))
    }

    private func recordFailure(_ failure: MCPServerError) {
        guard !isShuttingDown, terminalFailure == nil else { return }
        terminalFailure = failure
    }

    private func recordUnexpectedReceiveEnd(_ message: String) -> MCPServerError? {
        guard !isShuttingDown else {
            return nil
        }
        recordFailure(MCPServerError.transportFailure(
            operation: .receive,
            message: message
        ))
        return terminalFailure
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
        isConnecting = false
        isConnected = false
        isDisconnected = true
        disconnectTask = nil
    }
}
