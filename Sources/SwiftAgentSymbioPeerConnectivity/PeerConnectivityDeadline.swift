import NetworkingTime
import Synchronization

enum PeerConnectivityDeadlineCancellation: Sendable {
    case timedOut
    case callerCancelled
    case deadlineFailed
}

private final class PeerConnectivityDeadlineCoordinator: Sendable {
    enum Terminal: Sendable {
        case completed
        case timedOut
        case callerCancelled
        case deadlineFailed(PeerConnectivitySymbioError)
    }

    private struct State: Sendable {
        var terminal: Terminal?
        var waiter: CheckedContinuation<Terminal, Never>?
    }

    private let state = Mutex(State())

    func complete(
        beforeDeadline: Bool
    ) -> (terminal: Terminal, won: Bool) {
        let terminal: Terminal = beforeDeadline ? .completed : .timedOut
        return (terminal, transition(to: terminal))
    }

    @discardableResult
    func timeOut() -> Bool {
        transition(to: .timedOut)
    }

    func cancelFromCaller() {
        _ = transition(to: .callerCancelled)
    }

    func failDeadline(_ error: PeerConnectivitySymbioError) {
        _ = transition(to: .deadlineFailed(error))
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

private enum PeerConnectivityDeadlineOutcome<Value: Sendable>: Sendable {
    case operation(
        Result<Value, any Error>,
        terminal: PeerConnectivityDeadlineCoordinator.Terminal,
        wonTerminalRace: Bool
    )
    case timerFinished
    case cancellationFinished(Result<Void, any Error>)
    case completionObserved
}

func withPeerConnectivityDeadline<Value: Sendable>(
    _ duration: Duration,
    timer: any AsyncTimer = ContinuousAsyncTimer(),
    onCancellation: @escaping @Sendable (
        PeerConnectivityDeadlineCancellation
    ) async throws -> Void = { _ in },
    operation: @escaping @Sendable () async throws -> Value
) async throws -> Value {
    let nanoseconds = try durationNanoseconds(duration)
    let deadlineInstant: MonotonicInstant
    do {
        let now = try timer.now()
        deadlineInstant = try now.advanced(byNanoseconds: nanoseconds)
    } catch {
        throw deadlineFailure(error)
    }
    let coordinator = PeerConnectivityDeadlineCoordinator()

    let result = await withTaskCancellationHandler {
        await withTaskGroup(
            of: PeerConnectivityDeadlineOutcome<Value>.self,
            returning: Result<Value, any Error>.self
        ) { group in
            group.addTask {
                let result: Result<Value, any Error>
                do {
                    result = .success(try await operation())
                } catch {
                    result = .failure(error)
                }
                let transition: (
                    terminal: PeerConnectivityDeadlineCoordinator.Terminal,
                    won: Bool
                )
                do {
                    let completion = try timer.now()
                    guard completion.clockIdentifier
                            == deadlineInstant.clockIdentifier else {
                        throw TimeError.clockDomainMismatch(
                            expected: deadlineInstant.clockIdentifier,
                            actual: completion.clockIdentifier
                        )
                    }
                    transition = coordinator.complete(
                        beforeDeadline: completion.nanoseconds
                            < deadlineInstant.nanoseconds
                    )
                } catch {
                    let clockFailure: Result<Value, any Error> = .failure(
                        deadlineFailure(error)
                    )
                    let completion = coordinator.complete(beforeDeadline: true)
                    return .operation(
                        clockFailure,
                        terminal: completion.terminal,
                        wonTerminalRace: completion.won
                    )
                }
                return .operation(
                    result,
                    terminal: transition.terminal,
                    wonTerminalRace: transition.won
                )
            }
            group.addTask {
                do {
                    try await timer.sleep(until: deadlineInstant)
                    _ = coordinator.timeOut()
                } catch {
                    guard Task.isCancelled else {
                        coordinator.failDeadline(deadlineFailure(error))
                        return .timerFinished
                    }
                    // Operation completion or caller cancellation owns the terminal state.
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
                        return .cancellationFinished(.success(()))
                    } catch {
                        return .cancellationFinished(.failure(error))
                    }
                case .callerCancelled:
                    do {
                        try await onCancellation(.callerCancelled)
                        return .cancellationFinished(.success(()))
                    } catch {
                        return .cancellationFinished(.failure(error))
                    }
                case .deadlineFailed(_):
                    do {
                        try await onCancellation(.deadlineFailed)
                        return .cancellationFinished(.success(()))
                    } catch {
                        return .cancellationFinished(.failure(error))
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
                    case .timedOut, .callerCancelled, .deadlineFailed(_):
                        continue
                    }

                case .cancellationFinished(let cleanup):
                    group.cancelAll()
                    do {
                        try cleanup.get()
                    } catch {
                        return .failure(error)
                    }
                    switch await coordinator.waitForTerminal() {
                    case .timedOut:
                        return .failure(PeerConnectivitySymbioError.timeout)
                    case .deadlineFailed(let error):
                        return .failure(error)
                    case .callerCancelled, .completed:
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

private func durationNanoseconds(_ duration: Duration) throws -> UInt64 {
    guard duration > .zero else {
        throw PeerConnectivitySymbioError.timeout
    }
    let components = duration.components
    guard components.seconds >= 0, components.attoseconds >= 0,
          let seconds = UInt64(exactly: components.seconds),
          let attoseconds = UInt64(exactly: components.attoseconds) else {
        throw PeerConnectivitySymbioError.timeout
    }
    let remainder = attoseconds / 1_000_000_000
    guard seconds <= (UInt64.max - remainder) / 1_000_000_000 else {
        throw PeerConnectivitySymbioError.deadlineFailed(
            "Duration exceeds the monotonic timer range"
        )
    }
    return seconds * 1_000_000_000 + remainder
}

private func deadlineFailure(
    _ error: any Error
) -> PeerConnectivitySymbioError {
    if let typedError = error as? PeerConnectivitySymbioError {
        return typedError
    }
    return .deadlineFailed(String(describing: error))
}
