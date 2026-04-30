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
            debugLog("[AgentTurnExecutor] conversation.send completed sessionID=\(request.sessionID) turnID=\(request.turnID) outputLength=\(response.content.count) hasTextualStream=\(sink.hasTextualStream)")
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
            case .unsupportedInput: .failed
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
        sink.finish()

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
        guard let timeout else {
            return try await operation()
        }

        return try await withTaskCancellationHandler {
            let stream = AsyncThrowingStream<T, Error> { continuation in
                let operationTask = Task {
                    do {
                        continuation.yield(try await operation())
                        continuation.finish()
                    } catch {
                        continuation.finish(throwing: error)
                    }
                }

                let timeoutTask = Task {
                    do {
                        try await Task.sleep(for: timeout)
                        cancellationToken.cancel()
                        operationTask.cancel()
                        continuation.finish(throwing: AgentTurnExecutorError.timedOut(timeout))
                    } catch is CancellationError {
                    } catch {
                        continuation.finish(throwing: error)
                    }
                }

                continuation.onTermination = { @Sendable _ in
                    timeoutTask.cancel()
                    operationTask.cancel()
                }
            }

            for try await value in stream {
                return value
            }
            throw CancellationError()
        } onCancel: {
            cancellationToken.cancel()
        }
    }
}
