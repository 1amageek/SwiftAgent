import Synchronization

private final class SymbioDeadlineCoordinator: Sendable {
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

    func timeOut() {
        _ = transition(to: .timedOut)
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

private enum SymbioDeadlineOutcome<Value: Sendable>: Sendable {
    case operation(
        Result<Value, any Error>,
        terminal: SymbioDeadlineCoordinator.Terminal,
        wonTerminalRace: Bool
    )
    case timerFinished
    case terminalObserved(SymbioDeadlineCoordinator.Terminal)
}

func withSymbioDeadline<Value: Sendable>(
    _ duration: Duration,
    operation: @escaping @Sendable () async throws -> Value
) async throws -> Value {
    guard duration > .zero else {
        throw SymbioRuntimeError.invalidExecutionBudget
    }
    let clock = ContinuousClock()
    let deadline = clock.now.advanced(by: duration)
    let coordinator = SymbioDeadlineCoordinator()

    let result = await withTaskCancellationHandler {
        await withTaskGroup(
            of: SymbioDeadlineOutcome<Value>.self,
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
                    try await Task.sleep(for: duration)
                    coordinator.timeOut()
                } catch {
                    // Operation completion or caller cancellation owns the terminal state.
                }
                return .timerFinished
            }
            group.addTask {
                .terminalObserved(await coordinator.waitForTerminal())
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
                    group.cancelAll()
                    switch terminal {
                    case .completed:
                        return operationResult
                    case .timedOut:
                        return .failure(SymbioRuntimeError.deadlineExceeded)
                    case .callerCancelled:
                        return .failure(CancellationError())
                    }

                case .terminalObserved(let terminal):
                    switch terminal {
                    case .completed:
                        continue
                    case .timedOut:
                        group.cancelAll()
                        return .failure(SymbioRuntimeError.deadlineExceeded)
                    case .callerCancelled:
                        group.cancelAll()
                        return .failure(CancellationError())
                    }

                case .timerFinished:
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
