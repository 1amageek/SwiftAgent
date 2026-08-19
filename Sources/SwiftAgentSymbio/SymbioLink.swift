public protocol SymbioLink: Actor {
    /// Acquires the transport resources required by this link exactly once.
    /// A failed start remains shutdown-eligible so partial acquisition can be retried.
    func start() async throws

    /// Atomically replaces the desired local participant catalog.
    ///
    /// A successful return means the link owns the supplied desired state. The
    /// link is responsible for ordered delivery, retry, and reconciliation with
    /// connected peers. If this method throws, the previously accepted catalog
    /// remains authoritative.
    func synchronizeLocalParticipants(
        _ descriptors: [ParticipantDescriptor]
    ) async throws

    /// Receives the next link event through exactly one runtime-owned receive loop.
    /// `shutdown()` must unblock a suspended call by returning `nil` or throwing.
    func receive() async throws -> SymbioLinkEvent?

    /// Executes one remote invocation within the supplied end-to-end budget.
    /// Cancellation must release and drain transport work owned by the invocation.
    func invoke(
        _ envelope: SymbioInvocationEnvelope,
        on transportPeerID: TransportPeerID,
        timeout: Duration
    ) async throws -> SymbioInvocationReply

    /// Consumes a link-issued reply context exactly once and releases its channel.
    func send(
        _ reply: SymbioInvocationReply,
        to context: SymbioReplyContext
    ) async throws

    /// Rejects new work, unblocks `receive()`, and drains all owned I/O.
    /// Cleanup must outlive caller cancellation, concurrent callers must await
    /// the same owner operation, and a failure must remain observable and
    /// retryable on the next call.
    func shutdown() async throws
}
