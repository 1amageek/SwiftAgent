//
//  AgentTurnExecutor.swift
//  SwiftAgent
//

import Foundation

/// Executes one `RunRequest` against a `Conversation`.
///
/// This is the shared primitive behind transport-backed `AgentSession` turns
/// and programmatic `AgentSessionRunner` tasks.
struct AgentTurnExecutor: Sendable {
    private enum TimeoutOutcome<Value: Sendable>: Sendable {
        case operation(
            Result<Value, any Error>,
            TurnCancellationToken.Terminal
        )
        case terminal(TurnCancellationToken.Terminal?)
        case timerFinished
    }

    private let conversation: Conversation
    private let approvalHandler: (any ApprovalHandler)?
    private let eventHandler: @Sendable (RunEvent) async -> Void

    private nonisolated func debugLog(_ message: String) {
        if let data = "\(message)\n".data(using: .utf8) {
            FileHandle.standardError.write(data)
        }
    }

    init(
        conversation: Conversation,
        approvalHandler: (any ApprovalHandler)? = nil,
        eventHandler: @escaping @Sendable (RunEvent) async -> Void
    ) {
        self.conversation = conversation
        self.approvalHandler = approvalHandler
        self.eventHandler = eventHandler
    }

    func execute(
        request: RunRequest,
        cancellationToken: TurnCancellationToken = TurnCancellationToken()
    ) async -> RunResult {
        let start = ContinuousClock.now
        let sink = EventSink { event in
            await eventHandler(event)
        }

        await sink.emit(.runStarted(RunEvent.RunStarted(
            sessionID: request.sessionID,
            turnID: request.turnID
        )))
        #if DEBUG
        debugLog("[AgentTurnExecutor] runStarted sessionID=\(request.sessionID) turnID=\(request.turnID) timeout=\(String(describing: request.policy?.timeout))")
        #endif

        guard case .text(let text) = request.input else {
            if case .cancel = request.input {
                return await finish(
                    request: request,
                    sink: sink,
                    status: .cancelled,
                    finalOutput: nil,
                    error: nil,
                    start: start
                )
            }

            return await finish(
                request: request,
                sink: sink,
                status: .failed,
                finalOutput: nil,
                error: AgentTurnExecutorError.unsupportedInput(String(describing: request.input)),
                start: start
            )
        }

        if let steering = request.context?.steering {
            for item in steering {
                conversation.steer(item)
            }
        }

        let bridge = makeApprovalHandler(
            request: request,
            sink: sink
        )
        let sessionContext = AgentSessionContext(
            sessionID: request.sessionID,
            turnID: request.turnID
        )

        do {
            #if DEBUG
            debugLog("[AgentTurnExecutor] conversation.send begin sessionID=\(request.sessionID) turnID=\(request.turnID) inputLength=\(text.count)")
            #endif
            let response = try await withTimeout(
                request.policy?.timeout,
                cancellationToken: cancellationToken
            ) {
                try await AgentSessionContext.$current.withValue(sessionContext) {
                    try await TurnCancellationContext.withValue(cancellationToken) {
                        try await ApprovalHandlerContext.withValue(bridge) {
                            try await EventSinkContext.withValue(sink) {
                                try await conversation.send(text)
                            }
                        }
                    }
                }
            }
            #if DEBUG
            let hasTextualStream = sink.hasTextualStream
            debugLog("[AgentTurnExecutor] conversation.send completed sessionID=\(request.sessionID) turnID=\(request.turnID) outputLength=\(response.content.count) hasTextualStream=\(hasTextualStream)")
            #endif

            if !response.content.isEmpty && !sink.hasTextualStream {
                await sink.emitTokenDelta(
                    delta: response.content,
                    accumulated: response.content,
                    isComplete: true
                )
            }

            return await finish(
                request: request,
                sink: sink,
                status: .completed,
                finalOutput: response.content,
                error: nil,
                start: start
            )
        } catch let error as AgentTurnExecutorError {
            #if DEBUG
            debugLog("[AgentTurnExecutor] conversation.send executorError sessionID=\(request.sessionID) turnID=\(request.turnID) error=\(error)")
            #endif
            let status: RunStatus = switch error {
            case .timedOut: .timedOut
            case .unsupportedInput, .unexpectedCancellation: .failed
            }
            return await finish(
                request: request,
                sink: sink,
                status: status,
                finalOutput: nil,
                error: error,
                start: start
            )
        } catch is CancellationError {
            #if DEBUG
            debugLog("[AgentTurnExecutor] conversation.send cancelled sessionID=\(request.sessionID) turnID=\(request.turnID)")
            #endif
            return await finish(
                request: request,
                sink: sink,
                status: .cancelled,
                finalOutput: nil,
                error: nil,
                start: start
            )
        } catch {
            #if DEBUG
            debugLog("[AgentTurnExecutor] conversation.send failed sessionID=\(request.sessionID) turnID=\(request.turnID) type=\(type(of: error)) error=\(error)")
            #endif
            return await finish(
                request: request,
                sink: sink,
                status: .failed,
                finalOutput: nil,
                error: error,
                start: start
            )
        }
    }

    private func makeApprovalHandler(
        request: RunRequest,
        sink: EventSink
    ) -> (any ApprovalHandler)? {
        let handler: any ApprovalHandler
        if request.policy?.allowInteractiveApproval ?? true {
            guard let approvalHandler else {
                return nil
            }
            handler = approvalHandler
        } else {
            handler = AutoDenyApprovalHandler()
        }

        return ApprovalBridgeHandler(
            inner: handler,
            eventSink: sink,
            sessionID: request.sessionID,
            turnID: request.turnID
        )
    }

    private func finish(
        request: RunRequest,
        sink: EventSink,
        status: RunStatus,
        finalOutput: String?,
        error: (any Error)?,
        start: ContinuousClock.Instant
    ) async -> RunResult {
        let runError = error.map {
            RunEvent.RunError(
                message: $0.localizedDescription,
                isFatal: status == .failed || status == .timedOut,
                underlyingError: $0,
                sessionID: request.sessionID,
                turnID: request.turnID
            )
        }

        if let runError {
            await sink.emit(.error(runError))
        }

        await sink.emit(.runCompleted(RunEvent.RunCompleted(
            sessionID: request.sessionID,
            turnID: request.turnID,
            status: status
        )))
        #if DEBUG
        debugLog("[AgentTurnExecutor] runCompleted sessionID=\(request.sessionID) turnID=\(request.turnID) status=\(status) duration=\(ContinuousClock.now - start) finalOutputLength=\(finalOutput?.count ?? 0) error=\(String(describing: error))")
        #endif
        await sink.finish()

        return RunResult(
            sessionID: request.sessionID,
            turnID: request.turnID,
            status: status,
            finalOutput: finalOutput,
            error: runError,
            duration: ContinuousClock.now - start
        )
    }

    private func withTimeout<T: Sendable>(
        _ timeout: Duration?,
        cancellationToken: TurnCancellationToken,
        operation: @escaping @Sendable () async throws -> T
    ) async throws -> T {
        if let reason = cancellationToken.cancellationReason {
            try throwCancellation(reason)
        }
        if let timeout, timeout <= .zero {
            cancellationToken.cancelForTimeout(timeout)
            try throwCancellation(
                cancellationToken.cancellationReason ?? .timedOut(timeout)
            )
        }
        let clock = ContinuousClock()
        let deadline = timeout.map { clock.now.advanced(by: $0) }

        let result = await withTaskCancellationHandler {
            await withTaskGroup(
                of: TimeoutOutcome<T>.self,
                returning: Result<T, any Error>.self
            ) { group in
                group.addTask {
                    let result: Result<T, any Error>
                    do {
                        result = .success(try await operation())
                    } catch is CancellationError {
                        if Task.isCancelled
                            || cancellationToken.cancellationReason != nil {
                            result = .failure(CancellationError())
                        } else {
                            result = .failure(
                                AgentTurnExecutorError.unexpectedCancellation
                            )
                        }
                    } catch {
                        result = .failure(error)
                    }
                    let terminal = cancellationToken.settleOperation(
                        completedAt: clock.now,
                        deadline: deadline,
                        timeout: timeout
                    )
                    return .operation(result, terminal)
                }

                group.addTask {
                    .terminal(await cancellationToken.waitForTerminal())
                }

                if let timeout, let deadline {
                    group.addTask {
                        let remaining = clock.now.duration(to: deadline)
                        if remaining > .zero {
                            do {
                                try await Task.sleep(for: remaining)
                            } catch {
                                return .timerFinished
                            }
                        }
                        guard !Task.isCancelled else {
                            return .timerFinished
                        }
                        cancellationToken.cancelForTimeout(timeout)
                        return .terminal(cancellationToken.terminal)
                    }
                }

                while let outcome = await group.next() {
                    switch outcome {
                    case .operation(let operationResult, let terminal):
                        group.cancelAll()
                        switch terminal {
                        case .operationCompleted:
                            return operationResult
                        case .cancelled(let reason):
                            return .failure(Self.error(for: reason))
                        }

                    case .terminal(let observedTerminal):
                        let terminal = observedTerminal
                            ?? cancellationToken.terminal
                        guard let terminal else {
                            if Task.isCancelled {
                                group.cancelAll()
                                return .failure(CancellationError())
                            }
                            continue
                        }
                        switch terminal {
                        case .operationCompleted:
                            continue
                        case .cancelled(let reason):
                            group.cancelAll()
                            return .failure(Self.error(for: reason))
                        }

                    case .timerFinished:
                        continue
                    }
                }
                return .failure(CancellationError())
            }
        } onCancel: {
            cancellationToken.cancel()
        }

        return try result.get()
    }

    private static func error(
        for reason: TurnCancellationToken.CancellationReason
    ) -> any Error {
        switch reason {
        case .requested:
            return CancellationError()
        case .timedOut(let duration):
            return AgentTurnExecutorError.timedOut(duration)
        }
    }

    private func throwCancellation(
        _ reason: TurnCancellationToken.CancellationReason
    ) throws -> Never {
        switch reason {
        case .requested:
            throw CancellationError()
        case .timedOut(let duration):
            throw AgentTurnExecutorError.timedOut(duration)
        }
    }
}
