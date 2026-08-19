//
//  AgentSession.swift
//  SwiftAgent
//

import Foundation
import Synchronization

/// The orchestrator between an ``AgentConnection`` and `Conversation`.
///
/// `AgentSession` uses a two-task architecture:
/// - **Receive loop** (background Task): Always running, drains transport messages immediately
/// - **Turn processor** (main context): Executes turns sequentially from an internal queue
///
/// This separation ensures that `.approvalResponse` and `.cancel` messages
/// are processed promptly even while a turn is executing.
///
/// When a connection does **not** support concurrent receive, the receive loop
/// is paused during turn execution via a `TurnGate`. Such connections require a
/// ``TurnGatedApprovalHandler``; ``StdioApprovalHandler`` routes approval
/// through the same stdin owner instead of opening a competing reader.
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
/// let connection = StdioConnection(prompt: "> ")
/// let approvals = StdioApprovalHandler(connection: connection)
/// let session = AgentSession(connection: connection, approvalHandler: approvals)
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
    private nonisolated func debugLog(_ message: String) {
        #if DEBUG
        if let data = (message + "\n").data(using: .utf8) {
            FileHandle.standardError.write(data)
        }
        #endif
    }

    private enum Lifecycle {
        case idle
        case running
        case finished
    }

    private let connection: any AgentConnection
    private let approvalHandler: (any ApprovalHandler)?
    private let connectionApprovalHandler: ConnectionApprovalHandler?
    /// Generational tracker for completed turn IDs.
    ///
    /// Uses a two-generation design to bound memory:
    /// - `current`: actively collecting completed turnIDs.
    /// - `previous`: retained for lookups; evicted in bulk when `current` fills.
    /// - Lookups check both generations, so recently-evicted IDs are still recognized.
    /// - Total memory is bounded to approximately `2 * generationCapacity` entries.
    private let completedTurns: Mutex<CompletedTurnTracker>
    private let lifecycle = Mutex(Lifecycle.idle)

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
    static let turnQueueCapacity = 1_024

    private struct TurnState {
        /// Terminal session failures prevent buffered turns from starting.
        var isSessionAborted = false

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
    ///   - connection: The connection for receiving requests and sending events.
    ///   - approvalHandler: Optional approval handler for interactive approval flows.
    public init(
        connection: any AgentConnection,
        approvalHandler: (any ApprovalHandler)? = nil
    ) {
        self.connection = connection
        self.approvalHandler = approvalHandler
        self.connectionApprovalHandler = approvalHandler as? ConnectionApprovalHandler
        self.completedTurns = Mutex(CompletedTurnTracker())
        self.turnState = Mutex(TurnState())
    }

    /// Runs the agent session loop with a pre-built Conversation.
    ///
    /// Higher-level runtimes can build a `Conversation` themselves and invoke this primitive entry point.
    /// When using raw tools, prefer `run(tools:pipeline:instructions:step:)` so `EventEmittingMiddleware`
    /// and the configured pipeline are applied consistently.
    public func run(_ conversation: Conversation) async throws {
        if approvalHandler != nil,
           !connection.supportsConcurrentReceive,
           !(approvalHandler is any TurnGatedApprovalHandler) {
            throw AgentSessionError.approvalRequiresConcurrentReceive
        }
        let enteredRun = lifecycle.withLock { lifecycle -> Bool in
            guard case .idle = lifecycle else {
                return false
            }
            lifecycle = .running
            return true
        }
        guard enteredRun else {
            throw AgentSessionError.connectionAlreadyConsumed
        }
        defer {
            lifecycle.withLock { $0 = .finished }
        }

        let (turnStream, turnContinuation) = AsyncThrowingStream<RunRequest, Error>.makeStream(
            bufferingPolicy: .bufferingOldest(Self.turnQueueCapacity)
        )

        // Create TurnGate only for connections that cannot receive concurrently.
        let turnGate: TurnGate? = connection.supportsConcurrentReceive ? nil : TurnGate()

        // Background receive loop: captures only `self` (Sendable),
        // `turnContinuation` (Sendable), and `turnGate` (Sendable).
        // For connections with `supportsConcurrentReceive = false`,
        // the gate pauses this loop during turn execution to avoid stdin contention.
        let receiveTask = Task { [self, turnContinuation, turnGate] in
            defer { turnContinuation.finish() }
            while !Task.isCancelled {
                // Wait if a turn is currently executing (only for gated connections)
                if let turnGate {
                    await turnGate.waitIfNeeded()
                    guard !Task.isCancelled else {
                        return
                    }
                }

                let request: RunRequest
                do {
                    guard let nextRequest = try await self.connection.receive() else {
                        return
                    }
                    request = nextRequest
                } catch is CancellationError {
                    guard !Task.isCancelled else {
                        return
                    }
                    self.abortTrackedTurns()
                    turnContinuation.finish(throwing: CancellationError())
                    return
                } catch {
                    self.abortTrackedTurns()
                    turnContinuation.finish(throwing: error)
                    return
                }

                let alreadyCompleted = self.completedTurns.withLock { $0.contains(request.turnID) }
                guard !alreadyCompleted else { continue }

                switch request.input {
                case .text:
                    self.debugLog(
                        "[AgentSession] queued text turn sessionID=\(request.sessionID) turnID=\(request.turnID)"
                    )
                    // Close the receive gate before publishing the turn. The
                    // processor may resume as soon as yield succeeds and must
                    // never race an approval reader for the same connection.
                    turnGate?.enterTurn()
                    switch turnContinuation.yield(request) {
                    case .enqueued:
                        break
                    case .dropped:
                        turnGate?.leaveTurn()
                        self.abortTrackedTurns()
                        turnContinuation.finish(throwing: AgentSessionError.requestQueueFull(Self.turnQueueCapacity))
                        return
                    case .terminated:
                        turnGate?.leaveTurn()
                        return
                    @unknown default:
                        turnGate?.leaveTurn()
                        self.abortTrackedTurns()
                        turnContinuation.finish(throwing: AgentSessionError.requestQueueFull(Self.turnQueueCapacity))
                        return
                    }

                case .approvalResponse(let response):
                    if let handler = self.connectionApprovalHandler {
                        let decision = self.mapApprovalDecision(response.decision)
                        let didResolve = handler.resolve(
                            approvalID: response.approvalID,
                            decision: decision
                        )
                        if !didResolve {
                            let warning = RunEvent.WarningEvent(
                                message: "Received approvalResponse for unknown approvalID '\(response.approvalID)'.",
                                code: "APPROVAL_ID_UNKNOWN",
                                sessionID: request.sessionID,
                                turnID: request.turnID
                            )
                            do {
                                try await self.connection.send(.warning(warning))
                            } catch {
                                self.abortTrackedTurns()
                                turnContinuation.finish(throwing: error)
                                return
                            }
                        }
                    } else {
                        let warning = RunEvent.WarningEvent(
                            message: "Received approvalResponse for approvalID '\(response.approvalID)' but no ConnectionApprovalHandler is configured. The response was dropped.",
                            code: "APPROVAL_HANDLER_MISSING",
                            sessionID: request.sessionID,
                            turnID: request.turnID
                        )
                        do {
                            try await self.connection.send(.warning(warning))
                        } catch {
                            self.abortTrackedTurns()
                            turnContinuation.finish(throwing: error)
                            return
                        }
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
        var sessionError: (any Error)?
        await withTaskCancellationHandler {
            do {
                for try await request in turnStream {
                    debugLog(
                        "[AgentSession] processing turn sessionID=\(request.sessionID) turnID=\(request.turnID)"
                    )
                    // Definitive idempotency check: the receive loop checks at receive time,
                    // but a duplicate may pass if it arrives before the first attempt completes.
                    // This check runs after the previous turn finishes (sequential processing).
                    let alreadyCompleted = completedTurns.withLock { $0.contains(request.turnID) }
                    if alreadyCompleted {
                        turnGate?.leaveTurn()
                        continue
                    }
                    let token = TurnCancellationToken()
                    let sessionAborted = turnState.withLock { state -> Bool in
                        guard !state.isSessionAborted else {
                            return true
                        }
                        // Overwrites any sentinel (in either generation) from a previous cancelled attempt.
                        state.setToken(token, for: request.turnID)
                        if state.pendingCancels.remove(request.turnID) != nil {
                            token.cancel()
                        }
                        return false
                    }
                    guard !sessionAborted else {
                        turnGate?.leaveTurn()
                        continue
                    }
                    let result: RunResult
                    do {
                        result = try await executeTurn(
                            conversation: conversation,
                            request: request,
                            cancellationToken: token
                        )
                    } catch {
                        turnGate?.leaveTurn()
                        throw error
                    }
                    debugLog(
                        "[AgentSession] finished turn sessionID=\(request.sessionID) turnID=\(request.turnID)"
                    )
                    if result.status != .cancelled {
                        completedTurns.withLock { _ = $0.insert(request.turnID) }
                    }
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
            } catch {
                sessionError = error
            }
        } onCancel: {
            receiveTask.cancel()
            abortTrackedTurns()
            turnContinuation.finish(throwing: CancellationError())
        }

        receiveTask.cancel()
        connectionApprovalHandler?.rejectAll(error: sessionError ?? CancellationError())

        do {
            try await connection.shutdown()
        } catch {
            if let existingError = sessionError {
                sessionError = AgentSessionError.sessionAndShutdownFailed(
                    session: existingError.localizedDescription,
                    shutdown: error.localizedDescription
                )
            } else {
                sessionError = error
            }
        }
        _ = await receiveTask.result

        if let sessionError {
            throw sessionError
        }
    }

    // MARK: - Convenience Run (tools + pipeline)

    #if OpenFoundationModels
    /// Runs the agent session with tools dispatched through a `ToolRuntime`.
    ///
    /// The runtime installs middleware (event emitting, permission, sandbox)
    /// around every tool invocation and exposes type-erased forwarder tools
    /// to the LLM. Use this instead of `run(_ conversation:)` to guarantee
    /// tool event emission and security enforcement.
    ///
    /// ## Usage
    ///
    /// ```swift
    /// let connection = StdioConnection(prompt: "> ")
    /// let session = AgentSession(connection: connection)
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
    ///   - tools: The tools to make available. Registered as public tools on the runtime.
    ///   - configuration: The runtime configuration. Defaults to `.default`
    ///     (event emitting, permissive permission, no sandbox).
    ///   - instructions: System instructions for the language model.
    ///   - step: The processing step pipeline.
    public func run<S: Step & Sendable>(
        model: any LanguageModel,
        tools: [any Tool] = [],
        configuration: ToolRuntimeConfiguration = .default,
        @InstructionsBuilder instructions: @Sendable () -> Instructions,
        @StepBuilder step: @Sendable () -> S
    ) async throws where S.Input == Prompt, S.Output == String {
        var config = configuration
        config.register(tools)
        let runtime = ToolRuntime(configuration: config)
        let languageModelSession = LanguageModelSession(model: model, tools: runtime.publicTools()) {
            instructions()
        }
        let conversation = Conversation(languageModelSession: languageModelSession, step: step)
        try await run(conversation)
    }
    #else
    /// Runs the agent session with tools dispatched through a `ToolRuntime`.
    ///
    /// The runtime installs middleware (event emitting, permission, sandbox)
    /// around every tool invocation and exposes type-erased forwarder tools
    /// to the LLM. Use this instead of `run(_ conversation:)` to guarantee
    /// tool event emission and security enforcement.
    ///
    /// ## Usage
    ///
    /// ```swift
    /// let connection = StdioConnection(prompt: "> ")
    /// let session = AgentSession(connection: connection)
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
    ///   - tools: The tools to make available. Registered as public tools on the runtime.
    ///   - configuration: The runtime configuration. Defaults to `.default`
    ///     (event emitting, permissive permission, no sandbox).
    ///   - instructions: System instructions for the language model.
    ///   - step: The processing step pipeline.
    public func run<S: Step & Sendable>(
        tools: [any Tool] = [],
        configuration: ToolRuntimeConfiguration = .default,
        @InstructionsBuilder instructions: @Sendable () -> Instructions,
        @StepBuilder step: @Sendable () -> S
    ) async throws where S.Input == Prompt, S.Output == String {
        var config = configuration
        config.register(tools)
        let runtime = ToolRuntime(configuration: config)
        let languageModelSession = LanguageModelSession(tools: runtime.publicTools()) {
            instructions()
        }
        let conversation = Conversation(languageModelSession: languageModelSession, step: step)
        try await run(conversation)
    }
    #endif

    // MARK: - Turn Execution

    private func executeTurn(
        conversation: Conversation,
        request: RunRequest,
        cancellationToken: TurnCancellationToken
    ) async throws -> RunResult {
        let connection = self.connection
        let deliveryFailure = EventDeliveryFailure()
        let executor = AgentTurnExecutor(
            conversation: conversation,
            approvalHandler: approvalHandler
        ) { event in
            do {
                try await connection.send(event)
            } catch {
                deliveryFailure.record(error)
                cancellationToken.cancel()
            }
        }
        let result = await executor.execute(request: request, cancellationToken: cancellationToken)
        if let description = deliveryFailure.errorDescription {
            throw AgentSessionError.eventDeliveryFailed(description)
        }
        return result
    }

    // MARK: - Helpers

    private func abortTrackedTurns() {
        let tokens = turnState.withLock { state in
            state.isSessionAborted = true
            return Array(state.tokens.values) + Array(state.previousTokens.values)
        }
        for token in tokens {
            token.cancel()
        }
    }

    /// Maps an `ApprovalDecision` from the connection to a middleware response.
    private func mapApprovalDecision(_ decision: ApprovalDecision) -> PermissionResponse {
        switch decision {
        case .allowOnce: .allowOnce
        case .alwaysAllow: .alwaysAllow
        case .deny: .deny
        case .denyAndBlock: .denyAndBlock
        }
    }
}
