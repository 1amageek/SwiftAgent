//
//  HTTPSSETransport.swift
//  SwiftAgent
//

import Foundation
import Synchronization

/// An HTTP + Server-Sent Events transport for Agent I/O.
///
/// This transport is designed to be embedded in an HTTP server:
/// - Clients POST to `/turns` to submit `RunRequest`s
/// - Clients GET `/events` to receive `RunEvent`s as SSE
/// - Clients POST to `/approvals` to submit `ApprovalResponse`s
///
/// The transport itself does not start an HTTP server. Instead, it provides
/// methods for the server to enqueue requests and stream events.
///
/// ## Usage
///
/// ```swift
/// let transport = HTTPSSETransport()
///
/// // In your HTTP handler:
/// // POST /turns
/// func handleTurn(request: RunRequest) {
///     transport.enqueueRequest(request)
/// }
///
/// // GET /events
/// func handleEventStream() -> AsyncStream<RunEvent> {
///     transport.eventStream()
/// }
///
/// // Start the runtime
/// let runtime = AgentRuntime(transport: transport)
/// try await runtime.run(agent: myAgent, session: session)
/// ```
public final class HTTPSSETransport: AgentTransport, @unchecked Sendable {

    private let state: Mutex<TransportState>

    private struct TransportState {
        var requestBuffer: [RunRequest] = []
        var requestContinuation: CheckedContinuation<RunRequest, any Error>?
        var eventContinuations: [UUID: AsyncStream<RunEvent>.Continuation] = [:]
        var inputClosed = false
        var outputClosed = false
    }

    public init() {
        self.state = Mutex(TransportState())
    }

    // MARK: - Server-Side API

    /// Enqueues a request from the HTTP handler.
    ///
    /// If the runtime is waiting for a request, it is resumed immediately.
    /// Otherwise, the request is buffered.
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

    /// Returns an AsyncStream of events for SSE delivery.
    ///
    /// Each call creates a new subscriber. Multiple SSE clients can
    /// subscribe simultaneously.
    public func eventStream() -> AsyncStream<RunEvent> {
        let id = UUID()
        let (stream, continuation) = AsyncStream<RunEvent>.makeStream()
        state.withLock { $0.eventContinuations[id] = continuation }

        continuation.onTermination = { [weak self] _ in
            self?.state.withLock { _ = $0.eventContinuations.removeValue(forKey: id) }
        }

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
        let continuations = state.withLock { state -> [AsyncStream<RunEvent>.Continuation] in
            guard !state.outputClosed else { return [] }
            return Array(state.eventContinuations.values)
        }

        for continuation in continuations {
            continuation.yield(event)
        }
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
        let (requestCont, eventConts) = state.withLock { state -> (CheckedContinuation<RunRequest, any Error>?, [AsyncStream<RunEvent>.Continuation]) in
            state.inputClosed = true
            state.outputClosed = true
            let reqCont = state.requestContinuation
            state.requestContinuation = nil
            let evtConts = Array(state.eventContinuations.values)
            state.eventContinuations.removeAll()
            return (reqCont, evtConts)
        }

        requestCont?.resume(throwing: TransportError.inputClosed)
        for continuation in eventConts {
            continuation.finish()
        }
    }
}
