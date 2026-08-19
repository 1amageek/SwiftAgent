//
//  TurnCancellationToken.swift
//  SwiftAgent
//

import Foundation
import Synchronization

/// A cooperative cancellation token for turn-level cancellation.
///
/// Unlike `Task.cancel()`, which requires Sendable conformance on the agent,
/// `TurnCancellationToken` uses a shared flag that can be set from the receive loop
/// and checked at various checkpoints within the turn execution.
///
/// ## Usage
///
/// ```swift
/// let token = TurnCancellationToken()
///
/// // From receive loop (on .cancel):
/// token.cancel()
///
/// // From within turn execution:
/// try token.checkCancellation()  // throws CancellationError if cancelled
/// ```
public final class TurnCancellationToken: Sendable {
    enum CancellationReason: Sendable {
        case requested
        case timedOut(Duration)
    }

    enum Terminal: Sendable {
        case operationCompleted
        case cancelled(CancellationReason)
    }

    private struct State: Sendable {
        var reason: CancellationReason?
        var isOperationCompleted = false
        var waiters: [UUID: CheckedContinuation<CancellationReason, Never>] = [:]
        var terminalWaiters: [
            UUID: CheckedContinuation<Terminal?, Never>
        ] = [:]
    }

    private let state = Mutex(State())

    public init() {}

    /// Whether cancellation has been requested.
    public var isCancelled: Bool {
        state.withLock { $0.reason != nil }
    }

    var cancellationReason: CancellationReason? {
        state.withLock(\.reason)
    }

    var terminal: Terminal? {
        state.withLock { state in
            if let reason = state.reason {
                return .cancelled(reason)
            }
            return state.isOperationCompleted ? .operationCompleted : nil
        }
    }

    /// Throws `CancellationError` if cancellation has been requested.
    public func checkCancellation() throws {
        if isCancelled {
            throw CancellationError()
        }
    }

    /// Requests cancellation. Thread-safe; can be called from any context.
    public func cancel() {
        cancel(with: .requested)
    }

    func cancelForTimeout(_ timeout: Duration) {
        cancel(with: .timedOut(timeout))
    }

    /// Atomically settles operation completion against cancellation and the
    /// wall-clock deadline. The first terminal transition owns the result.
    func settleOperation(
        completedAt: ContinuousClock.Instant,
        deadline: ContinuousClock.Instant?,
        timeout: Duration?
    ) -> Terminal {
        let transition = state.withLock {
            state -> (
                terminal: Terminal,
                terminalWaiters: [CheckedContinuation<Terminal?, Never>],
                cancellationWaiters: [CheckedContinuation<CancellationReason, Never>]
            ) in
            if let reason = state.reason {
                return (.cancelled(reason), [], [])
            }
            if state.isOperationCompleted {
                return (.operationCompleted, [], [])
            }

            let terminal: Terminal
            var cancellationWaiters: [
                CheckedContinuation<CancellationReason, Never>
            ] = []
            if let deadline, let timeout, completedAt >= deadline {
                let reason = CancellationReason.timedOut(timeout)
                state.reason = reason
                terminal = .cancelled(reason)
                cancellationWaiters = Array(state.waiters.values)
                state.waiters.removeAll()
            } else {
                state.isOperationCompleted = true
                terminal = .operationCompleted
            }
            let terminalWaiters = Array(state.terminalWaiters.values)
            state.terminalWaiters.removeAll()
            return (terminal, terminalWaiters, cancellationWaiters)
        }
        for waiter in transition.terminalWaiters {
            waiter.resume(returning: transition.terminal)
        }
        if case .cancelled(let reason) = transition.terminal {
            for waiter in transition.cancellationWaiters {
                waiter.resume(returning: reason)
            }
        }
        return transition.terminal
    }

    func waitForTerminal() async -> Terminal? {
        let waiterID = UUID()
        return await withTaskCancellationHandler {
            await withCheckedContinuation { continuation in
                let registration = state.withLock {
                    state -> (terminal: Terminal?, shouldResume: Bool) in
                    if let reason = state.reason {
                        return (.cancelled(reason), true)
                    }
                    if state.isOperationCompleted {
                        return (.operationCompleted, true)
                    }
                    if Task.isCancelled {
                        return (nil, true)
                    }
                    state.terminalWaiters[waiterID] = continuation
                    return (nil, false)
                }
                if registration.shouldResume {
                    continuation.resume(returning: registration.terminal)
                }
            }
        } onCancel: {
            let waiter = state.withLock { state in
                state.terminalWaiters.removeValue(forKey: waiterID)
            }
            waiter?.resume(returning: nil)
        }
    }

    func waitForCancellation() async -> CancellationReason {
        let waiterID = UUID()
        return await withTaskCancellationHandler {
            await withCheckedContinuation { continuation in
                let immediateReason = state.withLock { state -> CancellationReason? in
                    if let reason = state.reason {
                        return reason
                    }
                    if Task.isCancelled {
                        return .requested
                    }
                    state.waiters[waiterID] = continuation
                    return nil
                }
                if let immediateReason {
                    continuation.resume(returning: immediateReason)
                }
            }
        } onCancel: {
            let waiter = state.withLock { state in
                state.waiters.removeValue(forKey: waiterID)
            }
            waiter?.resume(returning: .requested)
        }
    }

    private func cancel(with reason: CancellationReason) {
        let transition = state.withLock {
            state -> (
                cancellationWaiters: [CheckedContinuation<CancellationReason, Never>],
                terminalWaiters: [CheckedContinuation<Terminal?, Never>]
            ) in
            guard state.reason == nil, !state.isOperationCompleted else {
                return ([], [])
            }
            state.reason = reason
            let cancellationWaiters = Array(state.waiters.values)
            state.waiters.removeAll()
            let terminalWaiters = Array(state.terminalWaiters.values)
            state.terminalWaiters.removeAll()
            return (cancellationWaiters, terminalWaiters)
        }
        for waiter in transition.cancellationWaiters {
            waiter.resume(returning: reason)
        }
        for waiter in transition.terminalWaiters {
            waiter.resume(returning: .cancelled(reason))
        }
    }
}

/// TaskLocal context for propagating the active turn's cancellation token.
///
/// Follows the same pattern as `EventSinkContext` and `PermissionHandlerContext`.
public enum TurnCancellationContext: ContextKey {
    @TaskLocal private static var _current: TurnCancellationToken?

    public static var defaultValue: TurnCancellationToken? { nil }

    public static var current: TurnCancellationToken? { _current }

    public static func withValue<T: Sendable>(
        _ value: TurnCancellationToken?,
        operation: nonisolated(nonsending) () async throws -> T
    ) async rethrows -> T {
        try await $_current.withValue(value, operation: operation)
    }
}
