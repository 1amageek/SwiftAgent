//
//  AgentRuntime.swift
//  SwiftAgent
//

import Foundation
import Synchronization

/// The orchestrator between `AgentTransport` and `Agent`.
///
/// `AgentRuntime` uses a two-task architecture:
/// - **Receive loop** (background Task): Always running, drains transport messages immediately
/// - **Turn processor** (main context): Executes turns sequentially from an internal queue
///
/// This separation ensures that `.approvalResponse` and `.cancel` messages
/// are processed promptly even while a turn is executing.
///
/// When a transport does **not** support background receive (e.g., `StdioTransport`
/// shares stdin with `CLIPermissionHandler`), the receive loop is paused during
/// turn execution via a `TurnGate` to prevent stdin contention.
///
/// ## Usage
///
/// ```swift
/// let transport = StdioTransport()
/// let runtime = AgentRuntime(
///     transport: transport,
///     approvalHandler: LegacyApprovalAdapter(CLIPermissionHandler())
/// )
/// try await runtime.run(agent: MyAgent(), session: session)
/// ```
///
/// ## Turn Lifecycle
///
/// ```
/// receive(RunRequest)
///     → idempotency check (skip if turnID already completed)
///     → route by input type:
///         .text → enqueue to turn processor
///         .approvalResponse → resolve pending approval (immediate)
///         .cancel → signal cancellation to active turn via TurnCancellationToken
/// ```
public final class AgentRuntime: Sendable {

    private let transport: any AgentTransport
    private let approvalHandler: (any ApprovalHandler)?
    private let transportApprovalHandler: TransportApprovalHandler?
    private let completedTurns: Mutex<Set<String>>

    /// The active turn's cancellation token. Set at turn start, cancelled by `.cancel`.
    private let activeTurnToken: Mutex<TurnCancellationToken?>

    /// Creates an agent runtime.
    ///
    /// - Parameters:
    ///   - transport: The transport for receiving requests and sending events.
    ///   - approvalHandler: Optional approval handler for interactive approval flows.
    ///   - transportApprovalHandler: Optional transport-based approval handler for resolving approvals from transport messages.
    public init(
        transport: any AgentTransport,
        approvalHandler: (any ApprovalHandler)? = nil,
        transportApprovalHandler: TransportApprovalHandler? = nil
    ) {
        self.transport = transport
        self.approvalHandler = approvalHandler
        self.transportApprovalHandler = transportApprovalHandler
        self.completedTurns = Mutex([])
        self.activeTurnToken = Mutex(nil)
    }

    /// Runs the agent loop, processing requests from the transport until closed.
    ///
    /// This method blocks until the transport's input side is closed or the task is cancelled.
    /// Turns are processed sequentially — only one turn executes at a time.
    /// Approval responses and cancellation signals are handled concurrently
    /// via a background receive loop.
    ///
    /// - Parameters:
    ///   - agent: The agent to run.
    ///   - session: The language model session to inject.
    public func run<A: Agent>(agent: A, session: LanguageModelSession) async throws {
        let (turnStream, turnContinuation) = AsyncStream<RunRequest>.makeStream()

        // Create TurnGate only for transports that don't support background receive
        // (e.g., StdioTransport shares stdin with CLIPermissionHandler).
        let turnGate: TurnGate? = transport.supportsBackgroundReceive ? nil : TurnGate()

        // Background receive loop: captures only `self` (Sendable),
        // `turnContinuation` (Sendable), and `turnGate` (Sendable).
        // For transports with `supportsBackgroundReceive = false`,
        // the gate pauses this loop during turn execution to avoid stdin contention.
        let receiveTask = Task { [self, turnContinuation, turnGate] in
            defer { turnContinuation.finish() }
            while !Task.isCancelled {
                // Wait if a turn is currently executing (only for gated transports)
                if let turnGate {
                    await turnGate.waitIfNeeded()
                }

                let request: RunRequest
                do {
                    request = try await self.transport.receive()
                } catch is TransportError {
                    return
                } catch is CancellationError {
                    return
                } catch {
                    return
                }

                let alreadyCompleted = self.completedTurns.withLock { $0.contains(request.turnID) }
                guard !alreadyCompleted else { continue }

                switch request.input {
                case .text:
                    turnGate?.enterTurn()
                    turnContinuation.yield(request)

                case .approvalResponse(let response):
                    let decision = self.mapApprovalDecision(response.decision)
                    self.transportApprovalHandler?.resolve(
                        approvalID: response.approvalID,
                        decision: decision
                    )

                case .cancel:
                    self.activeTurnToken.withLock { $0?.cancel() }
                }
            }
        }

        // Turn processor: runs in the current async context (no Sendable
        // boundary crossing for agent/session). Processes turns sequentially.
        for await request in turnStream {
            let token = TurnCancellationToken()
            activeTurnToken.withLock { $0 = token }
            await executeTurn(agent: agent, session: session, request: request, cancellationToken: token)
            activeTurnToken.withLock { $0 = nil }
            turnGate?.leaveTurn()
        }

        // Clean shutdown
        _ = await receiveTask.result
        transportApprovalHandler?.rejectAll(error: CancellationError())
        await transport.close()
    }

    // MARK: - Turn Execution

    /// Executes a single turn: creates event stream, runs agent, forwards events.
    ///
    /// The `TurnCancellationToken` is injected into the execution context via
    /// `TurnCancellationContext`, making it available at checkpoints within
    /// `Agent.run()`, `Generate`, and `Loop`.
    ///
    /// Error handling:
    /// - Default `Agent.run()` catches all errors internally and returns `RunResult`.
    ///   In that case the `do` block succeeds and no catch block fires.
    /// - Custom `Agent.run()` overrides that throw are caught here,
    ///   emitting `.error` and `.runCompleted(.failed)` events.
    /// - `CancellationError` (from `.cancel`) emits `.runCompleted(.cancelled)`.
    ///   Cancelled turns are NOT marked as completed (allowing retry).
    private func executeTurn<A: Agent>(
        agent: A,
        session: LanguageModelSession,
        request: RunRequest,
        cancellationToken: TurnCancellationToken
    ) async {
        let (eventStream, continuation) = AsyncStream<RunEvent>.makeStream()
        let sink = EventSink(continuation: continuation)

        // Forward events to transport in background
        let transport = self.transport
        let forwardTask = Task {
            for await event in eventStream {
                do {
                    try await transport.send(event)
                } catch {
                    break
                }
            }
        }

        // Create approval bridge if handler is provided
        let bridge: (any PermissionHandler)? = approvalHandler.map { handler in
            ApprovalBridgeHandler(
                approvalHandler: handler,
                eventSink: sink,
                sessionID: request.sessionID,
                turnID: request.turnID
            )
        }

        do {
            let result = try await TurnCancellationContext.withValue(cancellationToken) {
                try await PermissionHandlerContext.withValue(bridge) {
                    try await EventSinkContext.withValue(sink) {
                        try await withSession(session) {
                            try await agent.run(request)
                        }
                    }
                }
            }
            // Default Agent.run() catches all errors internally and returns RunResult.
            // Mark terminal statuses as completed (except cancelled).
            switch result.status {
            case .completed, .failed, .denied, .timedOut:
                completedTurns.withLock { _ = $0.insert(request.turnID) }
            case .cancelled:
                // Cancelled turns are NOT marked as completed — client may retry.
                break
            }
        } catch is CancellationError {
            // Turn was cancelled. Emit cancellation event.
            // Only fires for custom Agent.run() overrides that rethrow CancellationError.
            await sink.emit(.runCompleted(RunEvent.RunCompleted(
                sessionID: request.sessionID,
                turnID: request.turnID,
                status: .cancelled
            )))
        } catch {
            // Unexpected error from a custom Agent.run() override.
            let runError = RunEvent.RunError(
                message: error.localizedDescription,
                isFatal: true,
                underlyingError: error,
                sessionID: request.sessionID,
                turnID: request.turnID
            )
            await sink.emit(.error(runError))
            await sink.emit(.runCompleted(RunEvent.RunCompleted(
                sessionID: request.sessionID,
                turnID: request.turnID,
                status: .failed
            )))
            completedTurns.withLock { _ = $0.insert(request.turnID) }
        }

        sink.finish()

        // Wait for event forwarding to drain
        _ = await forwardTask.result
    }

    // MARK: - Helpers

    /// Maps an `ApprovalDecision` (from transport) to `PermissionResponse` (for middleware).
    private func mapApprovalDecision(_ decision: ApprovalDecision) -> PermissionResponse {
        switch decision {
        case .allowOnce: .allowOnce
        case .alwaysAllow: .alwaysAllow
        case .deny: .deny
        case .denyAndBlock: .denyAndBlock
        }
    }
}

// MARK: - TurnGate

/// Controls the receive loop for transports that cannot receive while a turn executes.
///
/// When `StdioTransport` is used with `CLIPermissionHandler`, both compete for stdin.
/// `TurnGate` pauses the receive loop during turn execution to prevent this contention.
final class TurnGate: Sendable {
    private let state: Mutex<GateState>

    private struct GateState {
        var inTurn: Bool = false
        var waiters: [CheckedContinuation<Void, Never>] = []
    }

    init() {
        self.state = Mutex(GateState())
    }

    /// Called from the receive loop when a `.text` request is forwarded to the turn processor.
    /// Marks that a turn is about to execute, causing subsequent `waitIfNeeded()` calls to suspend.
    func enterTurn() {
        state.withLock { $0.inTurn = true }
    }

    /// Called from the turn processor after a turn completes.
    /// Resumes the receive loop so it can read the next request.
    func leaveTurn() {
        let waiters = state.withLock { state in
            state.inTurn = false
            let w = state.waiters
            state.waiters = []
            return w
        }
        for waiter in waiters {
            waiter.resume()
        }
    }

    /// Called at the top of the receive loop. Suspends if a turn is currently executing.
    func waitIfNeeded() async {
        let shouldWait: Bool = state.withLock { $0.inTurn }
        guard shouldWait else { return }

        await withCheckedContinuation { continuation in
            let resumed = state.withLock { state -> Bool in
                if state.inTurn {
                    state.waiters.append(continuation)
                    return false
                } else {
                    return true
                }
            }
            if resumed {
                continuation.resume()
            }
        }
    }
}
