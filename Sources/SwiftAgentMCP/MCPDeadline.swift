import Foundation
import Synchronization

enum MCPDeadlineCancellation: Sendable {
    case timedOut
    case callerCancelled
}

private final class MCPDeadlineCoordinator: Sendable {
    enum Terminal: Sendable {
        case completed
        case timedOut
        case callerCancelled
    }

    private struct State: Sendable {
        var terminal: Terminal?
        var waiter: CheckedContinuation<Terminal, Never>?
    }

    private let state = Mutex(State())

    func complete(
        at completion: ContinuousClock.Instant,
        before deadline: ContinuousClock.Instant
    ) -> (terminal: Terminal, won: Bool) {
        let terminal: Terminal = completion < deadline
            ? .completed
            : .timedOut
        return (terminal, transition(to: terminal))
    }

    @discardableResult
    func timeOut() -> Bool {
        transition(to: .timedOut)
    }

    func cancelFromCaller() {
        _ = transition(to: .callerCancelled)
    }

    func waitForTerminal() async -> Terminal {
        await withCheckedContinuation { continuation in
            let terminal = state.withLock { state -> Terminal? in
                if let terminal = state.terminal {
                    return terminal
                }
                precondition(state.waiter == nil)
                state.waiter = continuation
                return nil
            }
            if let terminal {
                continuation.resume(returning: terminal)
            }
        }
    }

    private func transition(to terminal: Terminal) -> Bool {
        let transition = state.withLock {
            state -> (won: Bool, waiter: CheckedContinuation<Terminal, Never>?) in
            guard state.terminal == nil else {
                return (false, nil)
            }
            state.terminal = terminal
            let waiter = state.waiter
            state.waiter = nil
            return (true, waiter)
        }
        transition.waiter?.resume(returning: terminal)
        return transition.won
    }
}

private enum MCPDeadlineOutcome<Value: Sendable>: Sendable {
    case operation(
        Result<Value, any Error>,
        terminal: MCPDeadlineCoordinator.Terminal,
        wonTerminalRace: Bool
    )
    case timerFinished
    case cancellationFinished(
        MCPDeadlineCancellation,
        Result<Void, any Error>
    )
    case completionObserved
}

func withMCPDeadline<Value: Sendable>(
    _ duration: Duration,
    timeoutError: @escaping @Sendable () -> any Error,
    onCancellation: @escaping @Sendable (
        MCPDeadlineCancellation
    ) async throws -> Void = { _ in },
    operation: @escaping @Sendable () async throws -> Value
) async throws -> Value {
    guard duration > .zero else {
        try await onCancellation(.timedOut)
        throw timeoutError()
    }
    let clock = ContinuousClock()
    let deadline = clock.now.advanced(by: duration)
    let coordinator = MCPDeadlineCoordinator()

    let result = await withTaskCancellationHandler {
        await withTaskGroup(
            of: MCPDeadlineOutcome<Value>.self,
            returning: Result<Value, any Error>.self
        ) { group in
            group.addTask {
                let result: Result<Value, any Error>
                do {
                    result = .success(try await operation())
                } catch {
                    result = .failure(error)
                }
                let transition = coordinator.complete(
                    at: clock.now,
                    before: deadline
                )
                return .operation(
                    result,
                    terminal: transition.terminal,
                    wonTerminalRace: transition.won
                )
            }
            group.addTask {
                do {
                    let remaining = clock.now.duration(to: deadline)
                    if remaining > .zero {
                        try await Task.sleep(for: remaining)
                    }
                    _ = coordinator.timeOut()
                } catch {
                    // Completion or caller cancellation owns the terminal state.
                }
                return .timerFinished
            }
            group.addTask {
                switch await coordinator.waitForTerminal() {
                case .completed:
                    return .completionObserved
                case .timedOut:
                    do {
                        try await onCancellation(.timedOut)
                        return .cancellationFinished(.timedOut, .success(()))
                    } catch {
                        return .cancellationFinished(.timedOut, .failure(error))
                    }
                case .callerCancelled:
                    do {
                        try await onCancellation(.callerCancelled)
                        return .cancellationFinished(
                            .callerCancelled,
                            .success(())
                        )
                    } catch {
                        return .cancellationFinished(
                            .callerCancelled,
                            .failure(error)
                        )
                    }
                }
            }

            while let outcome = await group.next() {
                switch outcome {
                case .operation(
                    let operationResult,
                    let terminal,
                    let wonTerminalRace
                ):
                    guard wonTerminalRace else {
                        continue
                    }
                    switch terminal {
                    case .completed:
                        group.cancelAll()
                        return operationResult
                    case .timedOut, .callerCancelled:
                        continue
                    }

                case .cancellationFinished(let cancellation, let cleanup):
                    group.cancelAll()
                    do {
                        try cleanup.get()
                    } catch {
                        return .failure(error)
                    }
                    switch cancellation {
                    case .timedOut:
                        return .failure(timeoutError())
                    case .callerCancelled:
                        return .failure(CancellationError())
                    }

                case .timerFinished, .completionObserved:
                    continue
                }
            }
            return .failure(CancellationError())
        }
    } onCancel: {
        coordinator.cancelFromCaller()
    }

    return try result.get()
}
