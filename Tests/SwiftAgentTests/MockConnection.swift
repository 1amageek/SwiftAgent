//
//  MockConnection.swift
//  SwiftAgentTests
//

import Foundation
import Synchronization
@testable import SwiftAgent

final class MockConnection: AgentConnection, Sendable {
    let supportsConcurrentReceive: Bool

    private let state: Mutex<State>

    private struct State: Sendable {
        var requests: [RunRequest] = []
        var waiters: [CheckedContinuation<RunRequest?, any Error>] = []
        var events: [RunEvent] = []
        var inputFinished = false
        var inputCancelled = false
        var outputFinished = false
        var inputFailure: MockConnectionError?
        var outputFailure: MockConnectionError?
    }

    init(supportsConcurrentReceive: Bool = true) {
        self.supportsConcurrentReceive = supportsConcurrentReceive
        self.state = Mutex(State())
    }

    func enqueue(_ request: RunRequest) {
        enum Action {
            case resume(CheckedContinuation<RunRequest?, any Error>)
            case buffered
            case ignored
        }

        let action = state.withLock { state -> Action in
            guard !state.inputFinished, !state.inputCancelled,
                  state.inputFailure == nil else {
                return .ignored
            }
            if !state.waiters.isEmpty {
                return .resume(state.waiters.removeFirst())
            }
            state.requests.append(request)
            return .buffered
        }

        if case .resume(let waiter) = action {
            waiter.resume(returning: request)
        }
    }

    func enqueueAndFinish(_ request: RunRequest) {
        enqueue(request)
        finishInput()
    }

    func finishInput() {
        let waiters = state.withLock { state -> [CheckedContinuation<RunRequest?, any Error>] in
            state.inputFinished = true
            let waiters = state.waiters
            state.waiters.removeAll()
            return waiters
        }
        for waiter in waiters {
            waiter.resume(returning: nil)
        }
    }

    func failInput(_ message: String) {
        let failure = MockConnectionError.injected(message)
        let waiters = state.withLock { state -> [CheckedContinuation<RunRequest?, any Error>] in
            state.inputFailure = failure
            let waiters = state.waiters
            state.waiters.removeAll()
            return waiters
        }
        for waiter in waiters {
            waiter.resume(throwing: failure)
        }
    }

    func cancelInputUnexpectedly() {
        let waiters = state.withLock { state -> [CheckedContinuation<RunRequest?, any Error>] in
            state.inputCancelled = true
            let waiters = state.waiters
            state.waiters.removeAll()
            return waiters
        }
        for waiter in waiters {
            waiter.resume(throwing: CancellationError())
        }
    }

    func failOutput(_ message: String) {
        state.withLock { $0.outputFailure = .injected(message) }
    }

    var collectedEvents: [RunEvent] {
        state.withLock { $0.events }
    }

    func receive() async throws -> RunRequest? {
        try await withCheckedThrowingContinuation { continuation in
            enum Action {
                case request(RunRequest)
                case end
                case failure(MockConnectionError)
                case cancelled
                case wait
            }

            let action = state.withLock { state -> Action in
                if let failure = state.inputFailure {
                    return .failure(failure)
                }
                if state.inputCancelled {
                    return .cancelled
                }
                if !state.requests.isEmpty {
                    return .request(state.requests.removeFirst())
                }
                if state.inputFinished {
                    return .end
                }
                state.waiters.append(continuation)
                return .wait
            }

            switch action {
            case .request(let request):
                continuation.resume(returning: request)
            case .end:
                continuation.resume(returning: nil)
            case .failure(let failure):
                continuation.resume(throwing: failure)
            case .cancelled:
                continuation.resume(throwing: CancellationError())
            case .wait:
                break
            }
        }
    }

    func send(_ event: RunEvent) async throws {
        try state.withLock { state in
            if let failure = state.outputFailure {
                throw failure
            }
            guard !state.outputFinished else {
                throw AgentConnectionError.outputClosed
            }
            state.events.append(event)
        }
    }

    func shutdown() async throws {
        finishInput()
        state.withLock { $0.outputFinished = true }
    }
}

enum MockConnectionError: Error, LocalizedError, Sendable, Equatable {
    case injected(String)

    var errorDescription: String? {
        switch self {
        case .injected(let message):
            message
        }
    }
}
