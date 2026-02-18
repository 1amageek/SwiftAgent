//
//  MockTransport.swift
//  SwiftAgent
//

import Foundation
import Synchronization
@testable import SwiftAgent

/// A mock transport for testing AgentSession.
///
/// Uses Continuation-based design for thread-safe request enqueuing
/// and event collection.
final class MockTransport: AgentTransport, @unchecked Sendable {
    let supportsBackgroundReceive: Bool

    private let _sentEvents: Mutex<[RunEvent]>
    private let _buffer: Mutex<[RunRequest]>
    private let _waiters: Mutex<[CheckedContinuation<RunRequest, any Error>]>
    private let _state: Mutex<TransportState>

    private struct TransportState {
        var inputClosed = false
        var outputClosed = false
    }

    init(supportsBackgroundReceive: Bool = true) {
        self.supportsBackgroundReceive = supportsBackgroundReceive
        self._sentEvents = Mutex([])
        self._buffer = Mutex([])
        self._waiters = Mutex([])
        self._state = Mutex(TransportState())
    }

    /// Enqueues a request for the runtime to receive.
    func enqueue(_ request: RunRequest) {
        let waiter = _waiters.withLock { w -> CheckedContinuation<RunRequest, any Error>? in
            if !w.isEmpty { return w.removeFirst() }
            return nil
        }
        if let waiter {
            waiter.resume(returning: request)
        } else {
            _buffer.withLock { $0.append(request) }
        }
    }

    /// Enqueues a request and then closes input.
    func enqueueAndClose(_ request: RunRequest) {
        enqueue(request)
        finishInput()
    }

    /// Closes the input side, failing all pending waiters.
    func finishInput() {
        _state.withLock { $0.inputClosed = true }
        let pending = _waiters.withLock { w in
            let copy = w; w.removeAll(); return copy
        }
        for waiter in pending {
            waiter.resume(throwing: TransportError.inputClosed)
        }
    }

    /// All events sent by the runtime.
    var collectedEvents: [RunEvent] {
        _sentEvents.withLock { Array($0) }
    }

    // MARK: - AgentTransport

    func receive() async throws -> RunRequest {
        let isClosed = _state.withLock { $0.inputClosed }
        let buffered = _buffer.withLock { b -> RunRequest? in
            if !b.isEmpty { return b.removeFirst() }
            return nil
        }
        if let request = buffered { return request }
        guard !isClosed else { throw TransportError.inputClosed }

        return try await withCheckedThrowingContinuation { continuation in
            let shouldFail = _state.withLock { $0.inputClosed }
            if shouldFail {
                continuation.resume(throwing: TransportError.inputClosed)
            } else {
                _waiters.withLock { $0.append(continuation) }
            }
        }
    }

    func send(_ event: RunEvent) async throws {
        let isClosed = _state.withLock { $0.outputClosed }
        guard !isClosed else { throw TransportError.outputClosed }
        _sentEvents.withLock { $0.append(event) }
    }

    func closeInput() async {
        finishInput()
    }

    func close() async {
        _state.withLock { s in s.inputClosed = true; s.outputClosed = true }
        finishInput()
    }
}
