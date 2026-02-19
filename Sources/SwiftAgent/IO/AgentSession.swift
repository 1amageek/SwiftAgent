//
//  AgentSession.swift
//  SwiftAgent
//

import Foundation
import Synchronization

/// The orchestrator between `AgentTransport` and `Conversation`.
///
/// `AgentSession` uses a two-task architecture:
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
/// let session = Conversation(
///     languageModelSession: LanguageModelSession(
///         model: SystemLanguageModel.default,
///         tools: [ReadTool(), ExecuteCommandTool()]
///     ) {
///         Instructions("You are a coding assistant.")
///     }
/// ) {
///     GenerateText { (input: String) in Prompt(input) }
/// }
///
/// let transport = StdioTransport(prompt: "> ")
/// let session = AgentSession(transport: transport, approvalHandler: CLIPermissionHandler())
/// try await session.run(conversation)
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
///         .cancel → match turnID to active token or record as pending cancel
/// ```
public final class AgentSession: Sendable {

    private let transport: any AgentTransport
    private let approvalHandler: (any ApprovalHandler)?
    private let transportApprovalHandler: TransportApprovalHandler?
    /// Generational tracker for completed turn IDs.
    ///
    /// Uses a two-generation design to bound memory:
    /// - `current`: actively collecting completed turnIDs.
    /// - `previous`: retained for lookups; evicted in bulk when `current` fills.
    /// - Lookups check both generations, so recently-evicted IDs are still recognized.
    /// - Total memory is bounded to approximately `2 * generationCapacity` entries.
    private let completedTurns: Mutex<CompletedTurnTracker>

    /// Per-turnID cancellation state: active tokens, sentinel tokens, and pre-emptive cancels.
    ///
    /// After a cancelled turn, its token remains as a **sentinel** across two generations.
    /// Late-arriving cancels hit the sentinel (idempotent `cancel()`) instead of
    /// leaking into `pendingCancels`, which would poison a retry.
    /// Terminal turns (completed/failed/denied/timedOut) are guarded by `completedTurns`,
    /// so their tokens are removed.
    /// Sentinel generations rotate when `current` exceeds `turnStateHighWaterMark`,
    /// ensuring sentinels survive at least one full cycle before eviction.
    private let turnState: Mutex<TurnState>

    /// High water mark for best-effort collections (`pendingCancels`, sentinel tokens).
    static let turnStateHighWaterMark = 10_000

    private struct TurnState {
        // MARK: - Sentinel tokens (two-generation)

        /// Current generation: active tokens and recent sentinels.
        var tokens: [String: TurnCancellationToken] = [:]
        /// Previous generation: older sentinels awaiting eviction.
        /// Lookups check both generations, so sentinels survive at least one
        /// full generation cycle (≥ `turnStateHighWaterMark` turns) before eviction.
        var previousTokens: [String: TurnCancellationToken] = [:]

        /// Looks up a token in both generations.
        func token(for turnID: String) -> TurnCancellationToken? {
            tokens[turnID] ?? previousTokens[turnID]
        }

        /// Sets a token in the current generation, promoting from previous if needed.
        mutating func setToken(_ token: TurnCancellationToken, for turnID: String) {
            tokens[turnID] = token
            previousTokens.removeValue(forKey: turnID)
        }

        /// Removes a token from both generations.
        mutating func removeToken(for turnID: String) {
            tokens.removeValue(forKey: turnID)
            previousTokens.removeValue(forKey: turnID)
        }

        /// Rotates generations when the current one exceeds capacity.
        mutating func rotateTokensIfNeeded(capacity: Int) {
            if tokens.count >= capacity {
                previousTokens = tokens
                tokens = [:]
            }
        }

        // MARK: - Pending cancels

        /// turnIDs whose cancel arrived before any token was created (first cancel ever for this turnID).
        /// Pre-emptive cancel is best-effort; eviction only loses the optimization.
        var pendingCancels: Set<String> = []
    }

    /// Two-generation set that bounds memory while retaining recent entries.
    ///
    /// When `current` reaches `generationCapacity`, it is promoted to `previous`
    /// and a fresh empty set becomes `current`. The old `previous` is discarded.
    /// Lookups check both generations, so entries survive for at least one full
    /// generation cycle before eviction.
    struct CompletedTurnTracker {
        private var current: Set<String> = []
        private var previous: Set<String> = []
        private let generationCapacity: Int

        init(generationCapacity: Int = 10_000) {
            self.generationCapacity = generationCapacity
        }

        /// Inserts a turnID. Rotates generations when `current` reaches capacity.
        @discardableResult
        mutating func insert(_ turnID: String) -> Bool {
            let (inserted, _) = current.insert(turnID)
            if current.count >= generationCapacity {
                previous = current
                current = []
            }
            return inserted
        }

        /// Returns `true` if the turnID exists in either generation.
        func contains(_ turnID: String) -> Bool {
            current.contains(turnID) || previous.contains(turnID)
        }
    }

    /// Creates an agent session.
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
        self.completedTurns = Mutex(CompletedTurnTracker())
        self.turnState = Mutex(TurnState())
    }

    /// Runs the agent session loop, processing requests from the transport until closed.
    ///
    /// This method blocks until the transport's input side is closed or the task is cancelled.
    /// Turns are processed sequentially — only one turn executes at a time.
    /// Approval responses and cancellation signals are handled concurrently
    /// via a background receive loop.
    ///
    /// - Parameter conversation: The agent session that handles message processing.
    public func run(_ conversation: Conversation) async throws {
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
                    if let handler = self.transportApprovalHandler {
                        let decision = self.mapApprovalDecision(response.decision)
                        handler.resolve(
                            approvalID: response.approvalID,
                            decision: decision
                        )
                    } else {
                        let warning = RunEvent.WarningEvent(
                            message: "Received approvalResponse for approvalID '\(response.approvalID)' but no TransportApprovalHandler is configured. The response was dropped.",
                            code: "APPROVAL_HANDLER_MISSING",
                            sessionID: request.sessionID,
                            turnID: request.turnID
                        )
                        try? await self.transport.send(.warning(warning))
                    }

                case .cancel:
                    self.turnState.withLock { state in
                        if let token = state.token(for: request.turnID) {
                            // Active turn or sentinel (both generations) — cancel() is idempotent.
                            token.cancel()
                        } else {
                            // Evict stale entries before inserting to bound memory.
                            // Pre-emptive cancel is best-effort; eviction only loses the optimization.
                            if state.pendingCancels.count >= Self.turnStateHighWaterMark {
                                state.pendingCancels.removeAll()
                            }
                            state.pendingCancels.insert(request.turnID)
                        }
                    }
                }
            }
        }

        // Turn processor: runs in the current async context (no Sendable
        // boundary crossing for conversation). Processes turns sequentially.
        for await request in turnStream {
            // Definitive idempotency check: the receive loop checks at receive time,
            // but a duplicate may pass if it arrives before the first attempt completes.
            // This check runs after the previous turn finishes (sequential processing).
            let alreadyCompleted = completedTurns.withLock { $0.contains(request.turnID) }
            if alreadyCompleted {
                turnGate?.leaveTurn()
                continue
            }
            let token = TurnCancellationToken()
            turnState.withLock { state in
                // Overwrites any sentinel (in either generation) from a previous cancelled attempt.
                state.setToken(token, for: request.turnID)
                if state.pendingCancels.remove(request.turnID) != nil {
                    token.cancel()
                }
            }
            await executeTurn(conversation: conversation, request: request, cancellationToken: token)
            let isTerminal = completedTurns.withLock { $0.contains(request.turnID) }
            turnState.withLock { state in
                if isTerminal {
                    // Terminal: completedTurns guards against future cancels.
                    state.removeToken(for: request.turnID)
                }
                // Cancelled: token stays as sentinel to absorb late cancels.
                // Retry will overwrite with a fresh token.
                state.pendingCancels.remove(request.turnID)

                // Rotate sentinel generations to bound memory. Sentinels survive
                // at least one full generation cycle before eviction, ensuring
                // late cancels within that window are absorbed (not leaked to pendingCancels).
                state.rotateTokensIfNeeded(capacity: Self.turnStateHighWaterMark)
            }
            turnGate?.leaveTurn()
        }

        // Clean shutdown
        _ = await receiveTask.result
        transportApprovalHandler?.rejectAll(error: CancellationError())
        await transport.close()
    }

    // MARK: - Convenience Run (tools + pipeline)

    #if OpenFoundationModels
    /// Runs the agent session with tools automatically wrapped by a `ToolPipeline`.
    ///
    /// This overload wraps the provided tools with `EventEmittingMiddleware` (and other
    /// middleware in the pipeline) before creating the `LanguageModelSession` and `Conversation`.
    /// Use this instead of `run(_ conversation:)` to guarantee tool event emission.
    ///
    /// ## Usage
    ///
    /// ```swift
    /// let transport = StdioTransport(prompt: "> ")
    /// let session = AgentSession(transport: transport)
    /// try await session.run(
    ///     model: myModel,
    ///     tools: [ReadTool(), WriteTool(), ExecuteCommandTool()]
    /// ) {
    ///     Instructions("You are a coding assistant.")
    /// } step: {
    ///     MyCodingAgent()
    /// }
    /// ```
    ///
    /// - Parameters:
    ///   - model: The language model to use.
    ///   - tools: The tools to make available. Automatically wrapped by `pipeline`.
    ///   - pipeline: The middleware pipeline. Defaults to `.default` (includes `EventEmittingMiddleware`).
    ///   - instructions: System instructions for the language model.
    ///   - step: The processing step pipeline.
    public func run<S: Step & Sendable>(
        model: any LanguageModel,
        tools: [any Tool] = [],
        pipeline: ToolPipeline = .default,
        @InstructionsBuilder instructions: @Sendable () -> Instructions,
        @StepBuilder step: @Sendable () -> S
    ) async throws where S.Input == String, S.Output == String {
        let wrappedTools = pipeline.wrap(tools)
        let languageModelSession = LanguageModelSession(model: model, tools: wrappedTools) {
            instructions()
        }
        let conversation = Conversation(languageModelSession: languageModelSession, step: step)
        try await run(conversation)
    }
    #else
    /// Runs the agent session with tools automatically wrapped by a `ToolPipeline`.
    ///
    /// This overload wraps the provided tools with `EventEmittingMiddleware` (and other
    /// middleware in the pipeline) before creating the `LanguageModelSession` and `Conversation`.
    /// Use this instead of `run(_ conversation:)` to guarantee tool event emission.
    ///
    /// ## Usage
    ///
    /// ```swift
    /// let transport = StdioTransport(prompt: "> ")
    /// let session = AgentSession(transport: transport)
    /// try await session.run(
    ///     tools: [ReadTool(), WriteTool(), ExecuteCommandTool()]
    /// ) {
    ///     Instructions("You are a coding assistant.")
    /// } step: {
    ///     MyCodingAgent()
    /// }
    /// ```
    ///
    /// - Parameters:
    ///   - tools: The tools to make available. Automatically wrapped by `pipeline`.
    ///   - pipeline: The middleware pipeline. Defaults to `.default` (includes `EventEmittingMiddleware`).
    ///   - instructions: System instructions for the language model.
    ///   - step: The processing step pipeline.
    public func run<S: Step & Sendable>(
        tools: [any Tool] = [],
        pipeline: ToolPipeline = .default,
        @InstructionsBuilder instructions: @Sendable () -> Instructions,
        @StepBuilder step: @Sendable () -> S
    ) async throws where S.Input == String, S.Output == String {
        let wrappedTools = pipeline.wrap(tools)
        let languageModelSession = LanguageModelSession(tools: wrappedTools) {
            instructions()
        }
        let conversation = Conversation(languageModelSession: languageModelSession, step: step)
        try await run(conversation)
    }
    #endif

    // MARK: - Turn Execution

    /// Executes a single turn: creates event stream, delegates to Conversation, forwards events.
    ///
    /// The `TurnCancellationToken` is injected into the execution context via
    /// `TurnCancellationContext`, making it available at checkpoints within
    /// `Generate` and `Loop`.
    ///
    /// Error handling:
    /// - `CancellationError` (from `.cancel`) emits `.runCompleted(.cancelled)`.
    ///   Cancelled turns are NOT marked as completed (allowing retry).
    /// - Other errors emit `.error` and `.runCompleted(.failed)`.
    private func executeTurn(
        conversation: Conversation,
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
        let bridge: (any ApprovalHandler)? = approvalHandler.map { handler in
            ApprovalBridgeHandler(
                inner: handler,
                eventSink: sink,
                sessionID: request.sessionID,
                turnID: request.turnID
            )
        }

        guard case .text(let text) = request.input else {
            await sink.emit(.runCompleted(RunEvent.RunCompleted(
                sessionID: request.sessionID,
                turnID: request.turnID,
                status: .failed
            )))
            sink.finish()
            _ = await forwardTask.result
            completedTurns.withLock { _ = $0.insert(request.turnID) }
            return
        }

        // Apply steering from request context
        if let steering = request.context?.steering {
            for s in steering { conversation.steer(s) }
        }

        await sink.emit(.runStarted(RunEvent.RunStarted(
            sessionID: request.sessionID,
            turnID: request.turnID
        )))

        let sessionContext = AgentSessionContext(
            sessionID: request.sessionID,
            turnID: request.turnID
        )

        do {
            let response = try await AgentSessionContext.$current.withValue(sessionContext) {
                try await TurnCancellationContext.withValue(cancellationToken) {
                    try await ApprovalHandlerContext.withValue(bridge) {
                        try await EventSinkContext.withValue(sink) {
                            try await conversation.send(text)
                        }
                    }
                }
            }

            // Emit final content
            if !response.content.isEmpty {
                await sink.emitTokenDelta(
                    delta: response.content,
                    accumulated: response.content,
                    isComplete: true
                )
            }

            await sink.emit(.runCompleted(RunEvent.RunCompleted(
                sessionID: request.sessionID,
                turnID: request.turnID,
                status: .completed
            )))
            completedTurns.withLock { _ = $0.insert(request.turnID) }
        } catch is CancellationError {
            await sink.emit(.runCompleted(RunEvent.RunCompleted(
                sessionID: request.sessionID,
                turnID: request.turnID,
                status: .cancelled
            )))
        } catch {
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
