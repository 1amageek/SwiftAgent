import Foundation
import Synchronization

/// Owns the bounded FIFO and atomically settles input against cancellation.
final class StdioLineBuffer: Sendable {
    private struct Waiter: Sendable {
        let id: UUID
        let continuation: CheckedContinuation<String?, any Error>
    }

    private enum Completion: Sendable {
        case open
        case finished
        case failed(AgentConnectionError)
    }

    private struct State: Sendable {
        var lines: [String] = []
        var waiters: [Waiter] = []
        var completion = Completion.open
    }

    private let capacity: Int
    private let state = Mutex(State())

    init(capacity: Int) {
        precondition(capacity > 0)
        self.capacity = capacity
    }

    func enqueue(_ line: String) -> Bool {
        let transition = state.withLock {
            state -> (
                accepted: Bool,
                waiter: CheckedContinuation<String?, any Error>?,
                failedWaiters: [CheckedContinuation<String?, any Error>]
            ) in
            guard case .open = state.completion else {
                return (false, nil, [])
            }
            if !state.waiters.isEmpty {
                let waiter = state.waiters.removeFirst().continuation
                return (true, waiter, [])
            }
            guard state.lines.count < capacity else {
                state.completion = .failed(.inputBufferFull(capacity))
                let waiters = state.waiters.map(\.continuation)
                state.waiters.removeAll()
                return (false, nil, waiters)
            }
            state.lines.append(line)
            return (true, nil, [])
        }

        transition.waiter?.resume(returning: line)
        for waiter in transition.failedWaiters {
            waiter.resume(throwing: AgentConnectionError.inputBufferFull(capacity))
        }
        return transition.accepted
    }

    func next() async throws -> String? {
        let waiterID = UUID()
        return try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { continuation in
                let immediate: Result<String?, any Error>? = state.withLock { state in
                    if Task.isCancelled {
                        return .failure(CancellationError())
                    }
                    if case .failed(let error) = state.completion {
                        return .failure(error)
                    }
                    if !state.lines.isEmpty {
                        return .success(state.lines.removeFirst())
                    }
                    switch state.completion {
                    case .open:
                        state.waiters.append(Waiter(
                            id: waiterID,
                            continuation: continuation
                        ))
                        return nil
                    case .finished:
                        return .success(nil)
                    case .failed(let error):
                        return .failure(error)
                    }
                }
                if let immediate {
                    continuation.resume(with: immediate)
                }
            }
        } onCancel: {
            cancelWaiter(waiterID)
        }
    }

    func finish(throwing error: AgentConnectionError? = nil) {
        let waiters = state.withLock { state -> [Waiter] in
            guard case .open = state.completion else {
                return []
            }
            state.completion = error.map(Completion.failed) ?? .finished
            let waiters = state.waiters
            state.waiters.removeAll()
            return waiters
        }
        for waiter in waiters {
            if let error {
                waiter.continuation.resume(throwing: error)
            } else {
                waiter.continuation.resume(returning: nil)
            }
        }
    }

    private func cancelWaiter(_ id: UUID) {
        let waiter = state.withLock { state -> Waiter? in
            guard let index = state.waiters.firstIndex(where: { $0.id == id }) else {
                return nil
            }
            return state.waiters.remove(at: index)
        }
        waiter?.continuation.resume(throwing: CancellationError())
    }
}
