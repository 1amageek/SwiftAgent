//
//  WebSocketTransport.swift
//  SwiftAgent
//

import Foundation
import Synchronization

/// A WebSocket transport for full-duplex Agent I/O.
///
/// Messages are JSON-encoded `RunRequest` (inbound) and `RunEvent` (outbound).
/// This is a skeleton implementation that provides the buffer/dispatch layer.
/// Actual WebSocket framing depends on the server framework (e.g., Vapor, Hummingbird).
///
/// ## Usage
///
/// ```swift
/// let transport = WebSocketTransport()
///
/// // In your WebSocket handler:
/// ws.onText { text in
///     let request = try JSONDecoder().decode(RunRequest.self, from: Data(text.utf8))
///     transport.enqueueRequest(request)
/// }
///
/// // Forward events
/// Task {
///     for await event in transport.outboundStream() {
///         let data = try JSONEncoder().encode(event)  // RunEvent Codable subset
///         ws.send(String(data: data, encoding: .utf8)!)
///     }
/// }
///
/// let runtime = AgentRuntime(transport: transport)
/// try await runtime.run(agent: myAgent, session: session)
/// ```
public final class WebSocketTransport: AgentTransport, @unchecked Sendable {

    private let state: Mutex<TransportState>

    private struct TransportState {
        var requestBuffer: [RunRequest] = []
        var requestContinuation: CheckedContinuation<RunRequest, any Error>?
        var outboundContinuation: AsyncStream<RunEvent>.Continuation?
        var inputClosed = false
        var outputClosed = false
    }

    public init() {
        self.state = Mutex(TransportState())
    }

    // MARK: - Server-Side API

    /// Enqueues a request received from the WebSocket.
    public func enqueueRequest(_ request: RunRequest) {
        let continuation = state.withLock { state -> CheckedContinuation<RunRequest, any Error>? in
            if let cont = state.requestContinuation {
                state.requestContinuation = nil
                return cont
            }
            state.requestBuffer.append(request)
            return nil
        }
        continuation?.resume(returning: request)
    }

    /// Returns an AsyncStream of outbound events to forward over the WebSocket.
    ///
    /// Only one consumer is expected (the WebSocket write handler).
    public func outboundStream() -> AsyncStream<RunEvent> {
        let (stream, continuation) = AsyncStream<RunEvent>.makeStream()
        state.withLock { $0.outboundContinuation = continuation }
        return stream
    }

    // MARK: - AgentTransport

    public func receive() async throws -> RunRequest {
        try await withCheckedThrowingContinuation { continuation in
            enum Action {
                case resume(RunRequest)
                case error
                case wait
            }

            let action = state.withLock { state -> Action in
                if state.inputClosed { return .error }
                if !state.requestBuffer.isEmpty {
                    return .resume(state.requestBuffer.removeFirst())
                }
                state.requestContinuation = continuation
                return .wait
            }

            switch action {
            case .resume(let request):
                continuation.resume(returning: request)
            case .error:
                continuation.resume(throwing: TransportError.inputClosed)
            case .wait:
                break
            }
        }
    }

    public func send(_ event: RunEvent) async throws {
        let continuation = state.withLock { state -> AsyncStream<RunEvent>.Continuation? in
            guard !state.outputClosed else { return nil }
            return state.outboundContinuation
        }
        continuation?.yield(event)
    }

    public func closeInput() async {
        let continuation = state.withLock { state -> CheckedContinuation<RunRequest, any Error>? in
            state.inputClosed = true
            let cont = state.requestContinuation
            state.requestContinuation = nil
            return cont
        }
        continuation?.resume(throwing: TransportError.inputClosed)
    }

    public func close() async {
        let (requestCont, outboundCont) = state.withLock { state -> (CheckedContinuation<RunRequest, any Error>?, AsyncStream<RunEvent>.Continuation?) in
            state.inputClosed = true
            state.outputClosed = true
            let reqCont = state.requestContinuation
            state.requestContinuation = nil
            let outCont = state.outboundContinuation
            state.outboundContinuation = nil
            return (reqCont, outCont)
        }

        requestCont?.resume(throwing: TransportError.inputClosed)
        outboundCont?.finish()
    }
}
