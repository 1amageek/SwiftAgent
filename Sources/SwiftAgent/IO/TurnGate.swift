import Foundation
import Synchronization

/// Controls the receive loop for connections that cannot receive while a turn executes.
///
/// `TurnGate` pauses normal request reads so a ``TurnGatedApprovalHandler`` can
/// use the connection-owned input path during turn execution.
final class TurnGate: Sendable {
    private struct State: Sendable {
        var inTurn = false
        var waiters: [UUID: CheckedContinuation<Void, Never>] = [:]
    }

    private let state = Mutex(State())

    func enterTurn() {
        state.withLock { $0.inTurn = true }
    }

    func leaveTurn() {
        let waiters = state.withLock { state in
            state.inTurn = false
            let waiters = Array(state.waiters.values)
            state.waiters.removeAll()
            return waiters
        }
        for waiter in waiters {
            waiter.resume()
        }
    }

    func waitIfNeeded() async {
        let waiterID = UUID()
        await withTaskCancellationHandler {
            await withCheckedContinuation { continuation in
                let shouldResume = state.withLock { state -> Bool in
                    guard state.inTurn, !Task.isCancelled else {
                        return true
                    }
                    state.waiters[waiterID] = continuation
                    return false
                }
                if shouldResume {
                    continuation.resume()
                }
            }
        } onCancel: {
            cancelWaiter(waiterID)
        }
    }

    private func cancelWaiter(_ waiterID: UUID) {
        let waiter = state.withLock { state in
            state.waiters.removeValue(forKey: waiterID)
        }
        waiter?.resume()
    }
}
