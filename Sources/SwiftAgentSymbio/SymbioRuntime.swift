import Foundation
import NetworkingCore

public actor SymbioRuntime {
    private enum State {
        case idle
        case starting
        case running
        case stopping
        case failed
        case cleanupFailed(SymbioRuntimeError)
        case finished
    }

    private enum LocalEndpointState: Equatable {
        case local
        case publishing(String)
        case published
        case withdrawing(String)
        case shuttingDown(String)

        var isExecutable: Bool {
            switch self {
            case .local, .published:
                return true
            case .publishing, .withdrawing, .shuttingDown:
                return false
            }
        }

        var isTransitioning: Bool {
            switch self {
            case .local, .published:
                return false
            case .publishing, .withdrawing, .shuttingDown:
                return true
            }
        }
    }

    private struct LocalEndpointRegistration {
        let handle: ParticipantHandle
        let endpoint: any ParticipantEndpoint
        var state: LocalEndpointState
    }

    private struct ChangeSubscriber {
        let id: String
        let continuation: AsyncThrowingStream<SymbioRuntimeChange, any Error>.Continuation
    }

    private struct RemoteClaimKey: Sendable, Hashable {
        let peerID: TransportPeerID
        let participantID: ParticipantID
    }

    private struct PendingClaimVerification: Sendable {
        let peerID: TransportPeerID
        let key: RemoteClaimKey
        let task: Task<Void, Never>
    }

    private struct PendingInboundInvocation: Sendable {
        let peerID: TransportPeerID
        let senderID: ParticipantID
        let recipientID: ParticipantID
        let task: Task<Void, Never>
    }

    public nonisolated let identity: ParticipantDescriptor
    public nonisolated let localHandle: ParticipantHandle

    private let link: any SymbioLink
    private let claimVerifier: any ParticipantClaimVerifier
    private let inboundAuthorizer: any InboundInvocationAuthorizer
    private let maximumInboundExecutionDuration: Duration
    private let maximumPendingInboundInvocations: Int
    private let maximumPendingClaimVerifications: Int

    private var state = State.idle
    private var participantRecords: [ParticipantID: ParticipantRecord]
    private var aggregateDescriptors: [ParticipantID: AggregateParticipantDescriptor] = [:]
    private var localRegistrations: [ParticipantID: LocalEndpointRegistration] = [:]
    private var remoteBindings: [ParticipantID: VerifiedParticipantBinding] = [:]
    private var connectedPeers: Set<TransportPeerID> = []
    private var peerGenerations: [TransportPeerID: UInt64] = [:]
    private var claimRevisions: [RemoteClaimKey: UInt64] = [:]
    private var claimVerificationTasks: [String: PendingClaimVerification] = [:]
    private var retiredClaimVerificationTasks: [String: Task<Void, Never>] = [:]
    private var monitorTask: Task<Void, Never>?
    private var inboundTasks: [String: PendingInboundInvocation] = [:]
    private var changeSubscribers: [String: ChangeSubscriber] = [:]
    private var stopOperationID: UUID?
    private var stopTask: Task<Result<Void, SymbioRuntimeError>, Never>?

    public init(
        identity: ParticipantDescriptor,
        link: any SymbioLink = LocalOnlySymbioLink(),
        claimVerifier: any ParticipantClaimVerifier = RejectingParticipantClaimVerifier(),
        inboundAuthorizer: any InboundInvocationAuthorizer = RejectingInboundInvocationAuthorizer(),
        maximumInboundExecutionDuration: Duration = .seconds(30),
        maximumPendingInboundInvocations: Int = 256,
        maximumPendingClaimVerifications: Int = 64
    ) throws {
        guard maximumInboundExecutionDuration > .zero else {
            throw SymbioRuntimeError.invalidExecutionBudget
        }
        guard maximumPendingInboundInvocations > 0 else {
            throw SymbioRuntimeError.invalidConfiguration(
                "inbound invocation capacity must be greater than zero"
            )
        }
        guard maximumPendingClaimVerifications > 0 else {
            throw SymbioRuntimeError.invalidConfiguration(
                "claim verification capacity must be greater than zero"
            )
        }
        try Self.validateDescriptor(identity)
        guard identity.capabilityContracts.isEmpty else {
            throw SymbioRuntimeError.runtimeIdentityAdvertisesCapabilities
        }

        let registrationID = UUID().uuidString
        self.identity = identity
        self.localHandle = ParticipantHandle(
            participantID: identity.id,
            registrationID: registrationID
        )
        self.link = link
        self.claimVerifier = claimVerifier
        self.inboundAuthorizer = inboundAuthorizer
        self.maximumInboundExecutionDuration = maximumInboundExecutionDuration
        self.maximumPendingInboundInvocations = maximumPendingInboundInvocations
        self.maximumPendingClaimVerifications = maximumPendingClaimVerifications
        self.participantRecords = [
            identity.id: ParticipantRecord(
                descriptor: identity,
                availability: .available(),
                declaredAffordances: identity.capabilityContracts.map { contract in
                    Affordance(
                        id: contract.id,
                        ownerID: identity.id,
                        contract: contract,
                        state: .available
                    )
                },
                claims: identity.selfClaims
            )
        ]
    }

    public func start() async throws {
        guard !hasLocalEndpointTransition else {
            throw SymbioRuntimeError.invalidLifecycle(
                "A participant lifecycle transition is still in progress"
            )
        }
        guard case .idle = state else {
            throw SymbioRuntimeError.invalidLifecycle("The runtime can only be started once")
        }
        state = .starting

        do {
            try await link.start()
            try await link.synchronizeLocalParticipants(localDescriptors)
        } catch {
            let startupError = error
            var cleanupFailures: [String] = []
            do {
                try await link.shutdown()
            } catch {
                cleanupFailures.append(error.localizedDescription)
            }
            state = .failed
            if !cleanupFailures.isEmpty {
                throw SymbioRuntimeError.cleanupFailed(
                    [startupError.localizedDescription] + cleanupFailures
                )
            }
            throw startupError
        }

        for participantID in Array(localRegistrations.keys) {
            localRegistrations[participantID]?.state = .published
        }
        state = .running
        startMonitoring()
    }

    public func stop() async throws {
        if let stopTask {
            let result = await stopTask.value
            try result.get()
            return
        }

        switch state {
        case .starting, .stopping:
            throw SymbioRuntimeError.invalidLifecycle("A lifecycle transition is already in progress")
        case .cleanupFailed:
            state = .stopping
        case .finished:
            return
        case .idle, .running, .failed:
            state = .stopping
        }

        let operationID = UUID()
        let task = Task { [self] () -> Result<Void, SymbioRuntimeError> in
            let result = await performStop()
            finishStopOperation(operationID)
            return result
        }
        stopOperationID = operationID
        stopTask = task

        let result = await task.value
        try result.get()
    }

    private func performStop() async -> Result<Void, SymbioRuntimeError> {
        monitorTask?.cancel()
        let monitorTask = self.monitorTask
        self.monitorTask = nil

        let activeInboundTasks = inboundTasks.values.map(\.task)
        inboundTasks.removeAll()
        for task in activeInboundTasks {
            task.cancel()
        }
        let activeClaimTasks = claimVerificationTasks.values.map(\.task)
            + Array(retiredClaimVerificationTasks.values)
        claimVerificationTasks.removeAll()
        retiredClaimVerificationTasks.removeAll()
        for task in activeClaimTasks {
            task.cancel()
        }

        let localEndpoints = localRegistrations.values.map(\.endpoint)
        for participantID in Array(localRegistrations.keys) {
            localRegistrations[participantID]?.state = .shuttingDown(
                UUID().uuidString
            )
        }
        markAllLocalParticipantsUnavailable(reason: "runtime stopped")
        connectedPeers.removeAll()
        markAllRemoteParticipantsUnavailable(reason: "runtime stopped")

        var failures: [String] = []
        do {
            try await link.shutdown()
        } catch {
            failures.append(error.localizedDescription)
        }

        await withTaskGroup(of: Void.self) { group in
            for endpoint in localEndpoints {
                group.addTask {
                    await endpoint.shutdown()
                }
            }
            await group.waitForAll()
        }

        for task in activeClaimTasks {
            await task.value
        }
        for task in activeInboundTasks {
            await task.value
        }
        await monitorTask?.value

        localRegistrations.removeAll()
        if failures.isEmpty {
            state = .finished
            finishChangeSubscribers()
            return .success(())
        } else {
            let error = SymbioRuntimeError.cleanupFailed(failures)
            state = .cleanupFailed(error)
            finishChangeSubscribers(throwing: error)
            return .failure(error)
        }
    }

    private func finishStopOperation(_ operationID: UUID) {
        guard stopOperationID == operationID else {
            return
        }
        stopOperationID = nil
        stopTask = nil
    }

    public var participantViews: [ParticipantView] {
        participantRecords.values
            .map(\.view)
            .sorted { $0.id.rawValue < $1.id.rawValue }
    }

    public var availableParticipants: [ParticipantView] {
        participantViews.filter(isRoutable)
    }

    public func participantView(for id: ParticipantID) -> ParticipantView? {
        participantRecords[id]?.view
    }

    public func changes(
        bufferingOldest capacity: Int = 128
    ) -> AsyncThrowingStream<SymbioRuntimeChange, any Error> {
        guard capacity > 0 else {
            let pair = AsyncThrowingStream<
                SymbioRuntimeChange,
                any Error
            >.makeStream(bufferingPolicy: .bufferingOldest(1))
            pair.continuation.finish(throwing: SymbioRuntimeError.invalidConfiguration(
                "change stream capacity must be greater than zero"
            ))
            return pair.stream
        }
        let pair = AsyncThrowingStream<SymbioRuntimeChange, any Error>.makeStream(
            bufferingPolicy: .bufferingOldest(capacity)
        )
        let id = UUID().uuidString
        changeSubscribers[id] = ChangeSubscriber(
            id: id,
            continuation: pair.continuation
        )
        pair.continuation.onTermination = { [weak self] _ in
            Task {
                await self?.removeChangeSubscriber(id)
            }
        }

        if case .finished = state {
            pair.continuation.finish()
            changeSubscribers.removeValue(forKey: id)
        } else if case .cleanupFailed(let error) = state {
            pair.continuation.finish(throwing: error)
            changeSubscribers.removeValue(forKey: id)
        }
        return pair.stream
    }

    @discardableResult
    public func register(
        _ endpoint: any ParticipantEndpoint
    ) async throws -> ParticipantHandle {
        guard stateAllowsRegistration else {
            throw SymbioRuntimeError.invalidLifecycle(
                "Participants cannot be registered in the current runtime state"
            )
        }
        let descriptor = endpoint.descriptor
        try Self.validateDescriptor(descriptor)
        guard !hasLocalEndpointTransition else {
            throw SymbioRuntimeError.localCatalogTransitionInProgress
        }
        guard descriptor.id != identity.id,
              localRegistrations[descriptor.id] == nil,
              remoteBindings[descriptor.id] == nil,
              aggregateDescriptors[descriptor.id] == nil else {
            throw SymbioRuntimeError.duplicateParticipant(descriptor.id)
        }

        let handle = ParticipantHandle(
            participantID: descriptor.id,
            registrationID: UUID().uuidString
        )
        guard case .running = state else {
            localRegistrations[descriptor.id] = LocalEndpointRegistration(
                handle: handle,
                endpoint: endpoint,
                state: .local
            )
            upsertParticipant(descriptor, availability: .available())
            return handle
        }

        let operationID = UUID().uuidString
        localRegistrations[descriptor.id] = LocalEndpointRegistration(
            handle: handle,
            endpoint: endpoint,
            state: .publishing(operationID)
        )
        do {
            try await link.synchronizeLocalParticipants(localDescriptors)
            guard case .running = state,
                  localRegistrations[descriptor.id]?.handle == handle,
                  localRegistrations[descriptor.id]?.state
                    == .publishing(operationID) else {
                throw SymbioRuntimeError.invalidLifecycle(
                    "Runtime state changed while publishing the participant"
                )
            }
            localRegistrations[descriptor.id]?.state = .published
            upsertParticipant(descriptor, availability: .available())
            return handle
        } catch {
            let publicationError = error
            let stillOwnsPublication = localRegistrations[descriptor.id]?.handle
                == handle
                && localRegistrations[descriptor.id]?.state
                    == .publishing(operationID)
            if stillOwnsPublication {
                let shutdownID = UUID().uuidString
                localRegistrations[descriptor.id]?.state = .shuttingDown(
                    shutdownID
                )
                await endpoint.shutdown()
                if localRegistrations[descriptor.id]?.handle == handle,
                   localRegistrations[descriptor.id]?.state
                    == .shuttingDown(shutdownID) {
                    localRegistrations.removeValue(forKey: descriptor.id)
                }
            }
            if let runtimeError = publicationError as? SymbioRuntimeError {
                throw runtimeError
            }
            throw SymbioRuntimeError.publicationFailed(
                participantID: descriptor.id,
                reason: publicationError.localizedDescription
            )
        }
    }

    public func remove(_ handle: ParticipantHandle) async throws {
        guard stateAllowsRemoval else {
            throw SymbioRuntimeError.invalidLifecycle(
                "Participants cannot be removed in the current runtime state"
            )
        }
        try validate(handle)
        guard handle.participantID != identity.id,
              var registration = localRegistrations[handle.participantID] else {
            throw SymbioRuntimeError.invalidParticipantHandle(handle.participantID)
        }
        guard !registration.state.isTransitioning else {
            throw SymbioRuntimeError.participantTransitionInProgress(
                handle.participantID
            )
        }
        guard !hasLocalEndpointTransition else {
            throw SymbioRuntimeError.localCatalogTransitionInProgress
        }

        let previousAvailability = participantRecords[handle.participantID]?
            .availability ?? .available()
        if case .running = state {
            let operationID = UUID().uuidString
            registration.state = .withdrawing(operationID)
            localRegistrations[handle.participantID] = registration
            updateAvailability(
                .unavailable(reason: "participant withdrawal in progress"),
                for: handle.participantID
            )
            do {
                try await link.synchronizeLocalParticipants(localDescriptors)
            } catch {
                if localRegistrations[handle.participantID]?.handle == handle,
                   localRegistrations[handle.participantID]?.state
                    == .withdrawing(operationID) {
                    localRegistrations[handle.participantID]?.state = .published
                    updateAvailability(
                        previousAvailability,
                        for: handle.participantID
                    )
                }
                throw SymbioRuntimeError.withdrawalFailed(
                    participantID: handle.participantID,
                    reason: error.localizedDescription
                )
            }
            guard localRegistrations[handle.participantID]?.handle == handle,
                  localRegistrations[handle.participantID]?.state
                    == .withdrawing(operationID) else {
                throw SymbioRuntimeError.participantTransitionInProgress(
                    handle.participantID
                )
            }
        }

        let shutdownID = UUID().uuidString
        localRegistrations[handle.participantID]?.state = .shuttingDown(
            shutdownID
        )
        participantRecords.removeValue(forKey: handle.participantID)
        emit(.left(handle.participantID))
        refreshAggregateAvailability()

        await registration.endpoint.shutdown()
        if localRegistrations[handle.participantID]?.handle == handle,
           localRegistrations[handle.participantID]?.state
            == .shuttingDown(shutdownID) {
            localRegistrations.removeValue(forKey: handle.participantID)
        }
    }

    public func register(_ aggregate: AggregateParticipantDescriptor) throws {
        guard stateAllowsRegistration else {
            throw SymbioRuntimeError.invalidLifecycle(
                "Aggregates cannot be registered in the current runtime state"
            )
        }
        guard aggregate.id != identity.id,
              localRegistrations[aggregate.id] == nil,
              remoteBindings[aggregate.id] == nil,
              aggregateDescriptors[aggregate.id] == nil else {
            throw SymbioRuntimeError.duplicateParticipant(aggregate.id)
        }
        try validateAggregate(aggregate)
        aggregateDescriptors[aggregate.id] = aggregate
        let descriptor = ParticipantDescriptor(
            id: aggregate.id,
            displayName: aggregate.displayName,
            kind: .aggregate,
            selfClaims: aggregate.members.map { member in
                Claim(
                    subjectID: aggregate.id,
                    predicate: "symbio.aggregate.member",
                    object: member.id.rawValue,
                    issuerID: aggregate.id
                )
            },
            metadata: aggregate.metadata.merging([
                "aggregate.kind": aggregate.kind.rawValue
            ]) { current, _ in current }
        )
        upsertParticipant(
            descriptor,
            availability: aggregateAvailability(for: aggregate)
        )
    }

    public func observe(_ evidence: Evidence) {
        var record = participantRecord(for: evidence.subjectID)
        record.evidence.append(evidence)
        participantRecords[evidence.subjectID] = record
        emit(.updated(record.view))
    }

    public func observe(_ affordance: Affordance) {
        var record = participantRecord(for: affordance.ownerID)
        record.recordObservedAffordance(affordance)
        participantRecords[affordance.ownerID] = record
        emit(.updated(record.view))
    }

    public func observe(_ trustView: TrustView) {
        var record = participantRecord(for: trustView.subjectID)
        record.trustViews.removeAll { $0.issuerID == trustView.issuerID }
        record.trustViews.append(trustView)
        participantRecords[trustView.subjectID] = record
        emit(.updated(record.view))
    }

    public func setAvailability(
        _ availability: Availability,
        for handle: ParticipantHandle
    ) throws {
        try validate(handle)
        updateAvailability(availability, for: handle.participantID)
    }

    public func block(_ id: ParticipantID, reason: String? = nil) {
        var record = participantRecord(for: id)
        record.isBlocked = true
        if let reason {
            record.constraints.append(reason)
        }
        participantRecords[id] = record
        cancelInboundInvocations(involving: id)
        emit(.updated(record.view))
        refreshAggregateAvailability()
    }

    public func forget(_ id: ParticipantID) throws {
        guard id != identity.id,
              localRegistrations[id] == nil else {
            throw SymbioRuntimeError.cannotForgetLocal(id)
        }
        guard remoteBindings[id] == nil else {
            throw SymbioRuntimeError.cannotForgetConnected(id)
        }
        guard participantRecords[id] != nil
                || aggregateDescriptors[id] != nil else {
            throw SymbioRuntimeError.participantNotFound(id)
        }
        participantRecords.removeValue(forKey: id)
        aggregateDescriptors.removeValue(forKey: id)
        emit(.left(id))
        refreshAggregateAvailability()
    }

    public func planRoute(for message: Message) -> RoutePlan {
        switch message.addressing {
        case .direct(let participantID):
            return routePlan(
                message: message,
                steps: [directStep(
                    message: message,
                    participantID: participantID
                )]
            )
        case .group(let participantIDs):
            return routePlan(
                message: message,
                steps: participantIDs
                    .sorted { $0.rawValue < $1.rawValue }
                    .map { directStep(
                        message: message,
                        participantID: $0
                    ) }
            )
        case .open:
            return routePlan(
                message: message,
                steps: [RoutePlanStep(
                    kind: .broadcast,
                    reasons: ["open message"]
                )]
            )
        }
    }

    public func authorize(
        _ plan: RoutePlan,
        using authorizer: any PolicyAuthorizer
    ) async -> RoutePlan {
        if let expiresAt = plan.expiresAt, expiresAt <= Date() {
            return plan.withPolicyDecision(PolicyDecision(
                state: .denied,
                policyIDs: [],
                reasons: ["route expired before authorization"]
            ))
        }
        guard !plan.requiredPolicies.isEmpty else {
            let rejected = plan.steps.contains { $0.kind == .reject }
            return plan.withPolicyDecision(PolicyDecision(
                state: rejected ? .denied : .approved,
                policyIDs: [],
                reasons: rejected
                    ? ["route contains rejected step"]
                    : ["no policy gate required"]
            ))
        }

        let decision = await authorizer.authorize(plan.policyRequest())
        if let expiresAt = plan.expiresAt, expiresAt <= Date() {
            return plan.withPolicyDecision(PolicyDecision(
                state: .denied,
                policyIDs: decision.policyIDs,
                reasons: ["route expired during authorization"]
            ))
        }
        guard decision.policyIDs.isSuperset(of: plan.requiredPolicies) else {
            return plan.withPolicyDecision(PolicyDecision(
                state: .denied,
                policyIDs: decision.policyIDs,
                reasons: ["authorizer did not decide every required policy"]
            ))
        }
        if let expiresAt = decision.expiresAt, expiresAt <= Date() {
            return plan.withPolicyDecision(PolicyDecision(
                state: .denied,
                policyIDs: decision.policyIDs,
                reasons: ["authorization decision expired before execution"]
            ))
        }
        return plan.withPolicyDecision(decision)
    }

    @discardableResult
    public func invoke(
        _ capability: String,
        on participantID: ParticipantID,
        representation: MessageRepresentation,
        with arguments: OwnedBytes,
        from sender: ParticipantHandle,
        authorizer: (any PolicyAuthorizer)? = nil,
        timeout: Duration = .seconds(30)
    ) async throws -> OwnedBytes? {
        guard timeout > .zero else {
            throw SymbioRuntimeError.invalidExecutionBudget
        }
        try validateSender(sender)
        guard case .running = state else {
            throw SymbioRuntimeError.invalidLifecycle(
                "The runtime must be running before invocation"
            )
        }

        let message = Message(
            senderID: sender.participantID,
            addressing: .direct(participantID),
            representation: representation,
            payload: arguments,
            intent: capability
        )
        let plan = try await executablePlan(
            for: message,
            target: participantID,
            authorizer: authorizer
        )
        guard case .running = state else {
            throw SymbioRuntimeError.invalidLifecycle(
                "The runtime stopped before invocation could begin"
            )
        }
        try validateSender(sender)
        try validateExecutable(plan, target: participantID)

        let envelope = SymbioInvocationEnvelope(
            senderID: sender.participantID,
            recipientID: participantID,
            capability: capability,
            representation: representation,
            arguments: arguments,
            executionBudget: timeout
        )

        if let registration = localRegistrations[participantID],
           registration.state.isExecutable,
           let senderDescriptor = participantRecords[sender.participantID]?.descriptor {
            do {
                let result = try await withSymbioDeadline(timeout) {
                    try await registration.endpoint.invoke(SymbioInvocation(
                        envelope: envelope,
                        principal: .local(senderDescriptor)
                    ))
                }
                guard case .running = state,
                      localRegistrations[participantID]?.handle
                        == registration.handle,
                      localRegistrations[participantID]?.state.isExecutable
                        == true,
                      participantRecords[participantID].map({
                          isRoutable($0.view)
                      }) == true else {
                    throw SymbioRuntimeError.participantUnavailable(
                        participantID
                    )
                }
                try validateSender(sender)
                recordInvocationEvidence(
                    Evidence(
                        subjectID: participantID,
                        kind: .successfulInvocation
                    ),
                    localHandle: registration.handle
                )
                return result
            } catch {
                let surfacedError: any Error
                if error is CancellationError, !Task.isCancelled {
                    surfacedError = SymbioRuntimeError.invocationFailed(
                        code: .internalError,
                        message: "Local endpoint cancelled without caller or runtime cancellation"
                    )
                } else {
                    surfacedError = error
                }
                recordInvocationEvidence(
                    Evidence(
                        subjectID: participantID,
                        kind: .failedInvocation,
                        message: surfacedError.localizedDescription
                    ),
                    localHandle: registration.handle
                )
                throw surfacedError
            }
        }

        guard let binding = remoteBindings[participantID] else {
            throw SymbioRuntimeError.participantUnavailable(participantID)
        }
        let reply: SymbioInvocationReply
        do {
            reply = try await link.invoke(
                envelope,
                on: binding.transportPeerID,
                timeout: timeout
            )
        } catch {
            let surfacedError: any Error
            if error is CancellationError, !Task.isCancelled {
                surfacedError = SymbioRuntimeError.invocationFailed(
                    code: .internalError,
                    message: "Remote link cancelled without caller or runtime cancellation"
                )
            } else {
                surfacedError = error
            }
            recordInvocationEvidence(
                Evidence(
                    subjectID: participantID,
                    kind: .failedInvocation,
                    message: surfacedError.localizedDescription
                ),
                remoteBinding: binding
            )
            throw surfacedError
        }
        guard case .running = state,
              remoteBindings[participantID] == binding,
              participantRecords[participantID].map({
                  isRoutable($0.view)
              }) == true else {
            throw SymbioRuntimeError.participantUnavailable(participantID)
        }
        try validateSender(sender)
        guard reply.invocationID == envelope.invocationID else {
            throw SymbioRuntimeError.invocationResponseMismatch(
                expected: envelope.invocationID,
                actual: reply.invocationID
            )
        }
        switch reply.outcome {
        case .success(let result):
            recordInvocationEvidence(
                Evidence(
                    subjectID: participantID,
                    kind: .successfulInvocation
                ),
                remoteBinding: binding
            )
            return result
        case .failure(let failure):
            recordInvocationEvidence(
                Evidence(
                    subjectID: participantID,
                    kind: .failedInvocation,
                    message: failure.message
                ),
                remoteBinding: binding
            )
            throw SymbioRuntimeError.invocationFailed(
                code: failure.code,
                message: failure.message
            )
        }
    }

    private var localDescriptors: [ParticipantDescriptor] {
        let endpointDescriptors = localRegistrations.values.compactMap {
            registration -> ParticipantDescriptor? in
            switch registration.state {
            case .local, .publishing, .published:
                return registration.endpoint.descriptor
            case .withdrawing, .shuttingDown:
                return nil
            }
        }
        return ([identity] + endpointDescriptors)
            .sorted { $0.id.rawValue < $1.id.rawValue }
    }

    private var hasLocalEndpointTransition: Bool {
        localRegistrations.values.contains { $0.state.isTransitioning }
    }

    private var stateAllowsRegistration: Bool {
        switch state {
        case .idle, .running:
            return true
        case .starting, .stopping, .failed, .cleanupFailed, .finished:
            return false
        }
    }

    private var stateAllowsRemoval: Bool {
        switch state {
        case .idle, .running, .failed:
            return true
        case .starting, .stopping, .cleanupFailed, .finished:
            return false
        }
    }

    private func validate(_ handle: ParticipantHandle) throws {
        if handle == localHandle {
            return
        }
        guard localRegistrations[handle.participantID]?.handle == handle else {
            throw SymbioRuntimeError.invalidParticipantHandle(
                handle.participantID
            )
        }
    }

    private func validateSender(_ handle: ParticipantHandle) throws {
        try validate(handle)
        guard let record = participantRecords[handle.participantID] else {
            throw SymbioRuntimeError.participantNotFound(handle.participantID)
        }
        guard !record.isBlocked else {
            throw SymbioRuntimeError.participantBlocked(handle.participantID)
        }
        guard record.availability.state == .available
                || record.availability.state == .degraded,
              record.availability.expiresAt.map({ $0 > Date() }) ?? true else {
            throw SymbioRuntimeError.participantUnavailable(
                handle.participantID
            )
        }
    }

    private func startMonitoring() {
        let link = self.link
        monitorTask = Task { [weak self] in
            do {
                while let event = try await link.receive() {
                    guard !Task.isCancelled else {
                        return
                    }
                    await self?.handleLinkEvent(event)
                }
                await self?.linkEnded()
            } catch is CancellationError {
                guard !Task.isCancelled else {
                    return
                }
                await self?.linkFailed(
                    SymbioRuntimeError.linkEndedUnexpectedly
                )
            } catch {
                await self?.linkFailed(error)
            }
        }
    }

    private func handleLinkEvent(_ event: SymbioLinkEvent) async {
        guard case .running = state else {
            return
        }
        switch event {
        case .peerConnected(let peerID):
            connect(peerID)
        case .peerClaimed(let claim):
            scheduleClaimVerification(claim)
        case .participantWithdrawn(let participantID, let peerID):
            withdrawRemoteParticipant(participantID, from: peerID)
        case .peerDisconnected(let peerID):
            disconnect(peerID)
        case .invocationReceived(let envelope, let replyContext):
            await scheduleInboundInvocation(
                envelope,
                replyContext: replyContext
            )
        case .diagnostic(let message):
            emit(.linkDiagnostic(message))
        }
    }

    private func connect(_ peerID: TransportPeerID) {
        guard connectedPeers.insert(peerID).inserted else {
            return
        }
        peerGenerations[peerID, default: 0] &+= 1
    }

    private func scheduleClaimVerification(_ claim: SymbioPeerClaim) {
        guard connectedPeers.contains(claim.transportPeerID),
              let generation = peerGenerations[claim.transportPeerID] else {
            emit(.participantClaimRejected(
                claim.transportPeerID,
                reason: "Participant claim arrived without a connected transport peer"
            ))
            return
        }
        guard !claim.authentication.method.trimmingCharacters(
            in: .whitespacesAndNewlines
        ).isEmpty,
        !claim.authentication.subject.trimmingCharacters(
            in: .whitespacesAndNewlines
        ).isEmpty else {
            emit(.participantClaimRejected(
                claim.transportPeerID,
                reason: "Participant authentication method and subject must not be empty"
            ))
            return
        }
        guard claimVerificationTasks.count
                + retiredClaimVerificationTasks.count
                < maximumPendingClaimVerifications else {
            emit(.participantClaimRejected(
                claim.transportPeerID,
                reason: "Participant claim verification capacity was exceeded"
            ))
            return
        }

        let key = RemoteClaimKey(
            peerID: claim.transportPeerID,
            participantID: claim.descriptor.id
        )
        claimRevisions[key, default: 0] &+= 1
        let revision = claimRevisions[key] ?? 0
        cancelClaimVerification(for: key)

        let taskID = UUID().uuidString
        let verifier = claimVerifier
        let task = Task { [weak self] in
            do {
                let binding = try await verifier.verify(claim)
                await self?.completeClaimVerification(
                    taskID: taskID,
                    claim: claim,
                    binding: binding,
                    failureReason: nil,
                    peerGeneration: generation,
                    claimRevision: revision
                )
            } catch is CancellationError {
                if Task.isCancelled {
                    await self?.discardClaimVerification(taskID: taskID)
                } else {
                    await self?.completeClaimVerification(
                        taskID: taskID,
                        claim: claim,
                        binding: nil,
                        failureReason: "Claim verifier cancelled without runtime cancellation",
                        peerGeneration: generation,
                        claimRevision: revision
                    )
                }
            } catch {
                await self?.completeClaimVerification(
                    taskID: taskID,
                    claim: claim,
                    binding: nil,
                    failureReason: error.localizedDescription,
                    peerGeneration: generation,
                    claimRevision: revision
                )
            }
        }
        claimVerificationTasks[taskID] = PendingClaimVerification(
            peerID: claim.transportPeerID,
            key: key,
            task: task
        )
    }

    private func completeClaimVerification(
        taskID: String,
        claim: SymbioPeerClaim,
        binding: VerifiedParticipantBinding?,
        failureReason: String?,
        peerGeneration: UInt64,
        claimRevision: UInt64
    ) {
        claimVerificationTasks.removeValue(forKey: taskID)
        retiredClaimVerificationTasks.removeValue(forKey: taskID)
        let key = RemoteClaimKey(
            peerID: claim.transportPeerID,
            participantID: claim.descriptor.id
        )
        guard case .running = state,
              connectedPeers.contains(claim.transportPeerID),
              peerGenerations[claim.transportPeerID] == peerGeneration,
              claimRevisions[key] == claimRevision else {
            return
        }
        guard let binding else {
            emit(.participantClaimRejected(
                claim.transportPeerID,
                reason: failureReason ?? "Participant claim verification failed"
            ))
            return
        }

        do {
            try validate(binding, for: claim)
            if let current = remoteBindings[binding.descriptor.id],
               current != binding {
                cancelInboundInvocations(from: binding.descriptor.id)
            }
            remoteBindings[binding.descriptor.id] = binding
            upsertParticipant(
                binding.descriptor,
                availability: .available()
            )
        } catch {
            emit(.participantClaimRejected(
                claim.transportPeerID,
                reason: error.localizedDescription
            ))
        }
    }

    private func validate(
        _ binding: VerifiedParticipantBinding,
        for claim: SymbioPeerClaim
    ) throws {
        try Self.validateDescriptor(binding.descriptor)
        guard binding.transportPeerID == claim.transportPeerID else {
            throw SymbioRuntimeError.invalidVerifiedBinding(
                "Verifier changed the transport peer identity"
            )
        }
        guard binding.descriptor.id == claim.descriptor.id else {
            throw SymbioRuntimeError.invalidVerifiedBinding(
                "Verifier changed the participant identity"
            )
        }
        guard !binding.descriptor.id.rawValue.isEmpty else {
            throw SymbioRuntimeError.invalidVerifiedBinding(
                "Verifier returned an empty participant identity"
            )
        }
        guard !binding.verificationMethod.trimmingCharacters(
            in: .whitespacesAndNewlines
        ).isEmpty else {
            throw SymbioRuntimeError.invalidVerifiedBinding(
                "Verifier returned an empty verification method"
            )
        }
        guard binding.descriptor.id != identity.id,
              localRegistrations[binding.descriptor.id] == nil,
              aggregateDescriptors[binding.descriptor.id] == nil else {
            throw SymbioRuntimeError.participantIdentityConflict(
                binding.descriptor.id
            )
        }
        if let current = remoteBindings[binding.descriptor.id],
           current.transportPeerID != binding.transportPeerID {
            throw SymbioRuntimeError.participantIdentityConflict(
                binding.descriptor.id
            )
        }
    }

    private func discardClaimVerification(taskID: String) {
        claimVerificationTasks.removeValue(forKey: taskID)
        retiredClaimVerificationTasks.removeValue(forKey: taskID)
    }

    private func cancelClaimVerification(for key: RemoteClaimKey) {
        let matching = claimVerificationTasks.filter { $0.value.key == key }
        for (taskID, pending) in matching {
            claimVerificationTasks.removeValue(forKey: taskID)
            retiredClaimVerificationTasks[taskID] = pending.task
            pending.task.cancel()
        }
    }

    private func disconnect(_ peerID: TransportPeerID) {
        cancelInboundInvocations(from: peerID)
        connectedPeers.remove(peerID)
        peerGenerations[peerID, default: 0] &+= 1
        let pending = claimVerificationTasks.filter {
            $0.value.peerID == peerID
        }
        for (taskID, verification) in pending {
            claimVerificationTasks.removeValue(forKey: taskID)
            retiredClaimVerificationTasks[taskID] = verification.task
            verification.task.cancel()
        }
        let disconnectedIDs = remoteBindings.values
            .filter { $0.transportPeerID == peerID }
            .map { $0.descriptor.id }
        for participantID in disconnectedIDs {
            remoteBindings.removeValue(forKey: participantID)
            updateAvailability(
                .unavailable(reason: "transport peer disconnected"),
                for: participantID
            )
        }
    }

    private func withdrawRemoteParticipant(
        _ participantID: ParticipantID,
        from peerID: TransportPeerID
    ) {
        let key = RemoteClaimKey(
            peerID: peerID,
            participantID: participantID
        )
        claimRevisions[key, default: 0] &+= 1
        cancelClaimVerification(for: key)
        guard remoteBindings[participantID]?.transportPeerID == peerID else {
            emit(.participantClaimRejected(
                peerID,
                reason: "Peer attempted to withdraw an identity it does not own"
            ))
            return
        }
        cancelInboundInvocations(from: participantID)
        remoteBindings.removeValue(forKey: participantID)
        updateAvailability(
            .unavailable(reason: "participant was withdrawn"),
            for: participantID
        )
    }

    private func scheduleInboundInvocation(
        _ envelope: SymbioInvocationEnvelope,
        replyContext: SymbioReplyContext
    ) async {
        guard inboundTasks[replyContext.id] == nil else {
            emit(.invocationRejected(
                envelope.invocationID,
                reason: "duplicate reply context"
            ))
            return
        }
        guard inboundTasks.count < maximumPendingInboundInvocations else {
            await rejectInboundInvocation(
                envelope,
                replyContext: replyContext,
                code: .overloaded,
                reason: "runtime inbound invocation capacity was exceeded"
            )
            return
        }
        let task = Task { [weak self] in
            guard let self else {
                return
            }
            await self.processInboundInvocation(
                envelope,
                replyContext: replyContext
            )
        }
        inboundTasks[replyContext.id] = PendingInboundInvocation(
            peerID: replyContext.transportPeerID,
            senderID: envelope.senderID,
            recipientID: envelope.recipientID,
            task: task
        )
    }

    private func rejectInboundInvocation(
        _ envelope: SymbioInvocationEnvelope,
        replyContext: SymbioReplyContext,
        code: SymbioInvocationFailureCode,
        reason: String
    ) async {
        emit(.invocationRejected(envelope.invocationID, reason: reason))
        do {
            try await link.send(
                .failure(
                    invocationID: envelope.invocationID,
                    code: code,
                    message: reason
                ),
                to: replyContext
            )
        } catch {
            emit(.invocationRejected(
                envelope.invocationID,
                reason: "Failed to deliver rejection reply: \(error.localizedDescription)"
            ))
        }
    }

    private func processInboundInvocation(
        _ envelope: SymbioInvocationEnvelope,
        replyContext: SymbioReplyContext
    ) async {
        let reply = await inboundReply(
            for: envelope,
            replyContext: replyContext
        )
        do {
            try await link.send(reply, to: replyContext)
        } catch {
            emit(.invocationRejected(
                envelope.invocationID,
                reason: "Failed to deliver invocation reply: \(error.localizedDescription)"
            ))
        }
        inboundTasks.removeValue(forKey: replyContext.id)
    }

    private func inboundReply(
        for envelope: SymbioInvocationEnvelope,
        replyContext: SymbioReplyContext
    ) async -> SymbioInvocationReply {
        guard envelope.executionBudget > .zero else {
            return .failure(
                invocationID: envelope.invocationID,
                code: .invalidRequest,
                message: "Execution budget must be greater than zero"
            )
        }
        let executionBudget = Swift.min(
            envelope.executionBudget,
            maximumInboundExecutionDuration
        )
        let clock = ContinuousClock()
        let deadline = clock.now.advanced(by: executionBudget)
        guard let binding = remoteBindings[envelope.senderID],
              binding.transportPeerID == replyContext.transportPeerID,
              let senderRecord = participantRecords[envelope.senderID],
              isRoutable(senderRecord.view) else {
            emit(.invocationRejected(
                envelope.invocationID,
                reason: "sender is not bound to the transport peer"
            ))
            return .failure(
                invocationID: envelope.invocationID,
                code: .unauthorized,
                message: "Sender identity is not authorized"
            )
        }
        guard let registration = localRegistrations[envelope.recipientID],
              registration.state.isExecutable,
              let recipientRecord = participantRecords[envelope.recipientID],
              isRoutable(recipientRecord.view) else {
            return .failure(
                invocationID: envelope.invocationID,
                code: .notFound,
                message: "Recipient is not available"
            )
        }
        let endpoint = registration.endpoint
        let recipient = endpoint.descriptor
        guard recipient.capabilityContracts.contains(where: {
            $0.id == envelope.capability
                && $0.input == envelope.representation
        }) else {
            return .failure(
                invocationID: envelope.invocationID,
                code: .invalidRequest,
                message: "Capability contract does not match the invocation"
            )
        }

        do {
            let authorizationBudget = try remainingDuration(
                until: deadline,
                measuredBy: clock
            )
            let authorizer = inboundAuthorizer
            let request = InboundInvocationRequest(
                binding: binding,
                envelope: envelope,
                recipient: recipient
            )
            let decision = try await withSymbioDeadline(authorizationBudget) {
                try await authorizer.authorize(request)
            }
            guard case .allow = decision else {
                let reason: String
                switch decision {
                case .allow:
                    reason = "Invocation allowed"
                case .deny(let deniedReason):
                    reason = deniedReason
                }
                emit(.invocationRejected(
                    envelope.invocationID,
                    reason: reason
                ))
                return .failure(
                    invocationID: envelope.invocationID,
                    code: .unauthorized,
                    message: "Invocation denied by policy"
                )
            }

            guard let currentBinding = remoteBindings[envelope.senderID],
                  currentBinding == binding,
                  participantRecords[envelope.senderID].map({
                    isRoutable($0.view)
                  }) == true,
                  case .running = state,
                  localRegistrations[envelope.recipientID]?.handle
                    == registration.handle,
                  localRegistrations[envelope.recipientID]?
                    .state.isExecutable == true,
                  participantRecords[envelope.recipientID].map({
                    isRoutable($0.view)
                  }) == true else {
                return .failure(
                    invocationID: envelope.invocationID,
                    code: .unavailable,
                    message: "Invocation participants changed during authorization"
                )
            }

            let remainingExecutionBudget = try remainingDuration(
                until: deadline,
                measuredBy: clock
            )
            let result = try await withSymbioDeadline(remainingExecutionBudget) {
                try await endpoint.invoke(SymbioInvocation(
                    envelope: envelope,
                    principal: .remote(binding)
                ))
            }
            guard case .running = state,
                  remoteBindings[envelope.senderID] == binding,
                  participantRecords[envelope.senderID].map({
                      isRoutable($0.view)
                  }) == true,
                  localRegistrations[envelope.recipientID]?.handle
                    == registration.handle,
                  localRegistrations[envelope.recipientID]?
                    .state.isExecutable == true,
                  participantRecords[envelope.recipientID].map({
                      isRoutable($0.view)
                  }) == true else {
                return .failure(
                    invocationID: envelope.invocationID,
                    code: .unavailable,
                    message: "Invocation participants changed during execution"
                )
            }
            recordInvocationEvidence(
                Evidence(
                    subjectID: envelope.senderID,
                    kind: .successfulInvocation
                ),
                remoteBinding: binding
            )
            return .success(
                invocationID: envelope.invocationID,
                result: result
            )
        } catch SymbioRuntimeError.deadlineExceeded {
            return .failure(
                invocationID: envelope.invocationID,
                code: .deadlineExceeded,
                message: "Invocation deadline exceeded"
            )
        } catch is CancellationError where Task.isCancelled {
            return .failure(
                invocationID: envelope.invocationID,
                code: .unavailable,
                message: "Invocation ownership context is no longer available"
            )
        } catch {
            recordInvocationEvidence(
                Evidence(
                    subjectID: envelope.senderID,
                    kind: .failedInvocation,
                    message: error.localizedDescription
                ),
                remoteBinding: binding
            )
            return .failure(
                invocationID: envelope.invocationID,
                code: .internalError,
                message: "Participant execution failed"
            )
        }
    }

    private func remainingDuration(
        until deadline: ContinuousClock.Instant,
        measuredBy clock: ContinuousClock
    ) throws -> Duration {
        let remaining = clock.now.duration(to: deadline)
        guard remaining > .zero else {
            throw SymbioRuntimeError.deadlineExceeded
        }
        return remaining
    }

    private func linkEnded() {
        guard case .running = state else {
            return
        }
        state = .failed
        cancelTransportDerivedTasks()
        connectedPeers.removeAll()
        markAllLocalParticipantsUnavailable(reason: "link ended")
        markAllRemoteParticipantsUnavailable(reason: "link ended")
        emit(.linkFailed(
            SymbioRuntimeError.linkEndedUnexpectedly.localizedDescription
        ))
    }

    private func linkFailed(_ error: any Error) {
        guard case .running = state else {
            return
        }
        state = .failed
        cancelTransportDerivedTasks()
        connectedPeers.removeAll()
        markAllLocalParticipantsUnavailable(reason: "link failed")
        markAllRemoteParticipantsUnavailable(reason: "link failed")
        emit(.linkFailed(error.localizedDescription))
    }

    private func markAllRemoteParticipantsUnavailable(reason: String) {
        let participantIDs = remoteBindings.keys
        remoteBindings.removeAll()
        for participantID in participantIDs {
            updateAvailability(
                .unavailable(reason: reason),
                for: participantID
            )
        }
    }

    private func cancelInboundInvocations(from peerID: TransportPeerID) {
        for pending in inboundTasks.values where pending.peerID == peerID {
            pending.task.cancel()
        }
    }

    private func cancelInboundInvocations(from senderID: ParticipantID) {
        for pending in inboundTasks.values where pending.senderID == senderID {
            pending.task.cancel()
        }
    }

    private func cancelInboundInvocations(involving participantID: ParticipantID) {
        for pending in inboundTasks.values
            where pending.senderID == participantID
                || pending.recipientID == participantID {
            pending.task.cancel()
        }
    }

    private func cancelTransportDerivedTasks() {
        for (taskID, verification) in claimVerificationTasks {
            retiredClaimVerificationTasks[taskID] = verification.task
            verification.task.cancel()
        }
        claimVerificationTasks.removeAll()
        for pending in inboundTasks.values {
            pending.task.cancel()
        }
    }

    private func markAllLocalParticipantsUnavailable(reason: String) {
        let participantIDs = Set(localRegistrations.keys).union([identity.id])
        for participantID in participantIDs {
            updateAvailability(
                .unavailable(reason: reason),
                for: participantID
            )
        }
    }

    private func recordInvocationEvidence(
        _ evidence: Evidence,
        localHandle: ParticipantHandle? = nil,
        remoteBinding: VerifiedParticipantBinding? = nil
    ) {
        guard case .running = state,
              var record = participantRecords[evidence.subjectID] else {
            return
        }
        if let localHandle {
            guard let registration = localRegistrations[evidence.subjectID],
                  registration.handle == localHandle,
                  registration.state.isExecutable else {
                return
            }
        }
        if let remoteBinding {
            guard remoteBindings[evidence.subjectID] == remoteBinding else {
                return
            }
        }
        record.evidence.append(evidence)
        participantRecords[evidence.subjectID] = record
        emit(.updated(record.view))
    }

    private func upsertParticipant(
        _ descriptor: ParticipantDescriptor,
        availability: Availability
    ) {
        let declared = declaredAffordances(
            for: descriptor,
            availability: availability
        )
        if var record = participantRecords[descriptor.id] {
            record.descriptor = descriptor
            record.availability = availability
            record.replaceDeclaredAffordances(declared)
            record.claims = descriptor.selfClaims
            participantRecords[descriptor.id] = record
            emit(.updated(record.view))
        } else {
            let record = ParticipantRecord(
                descriptor: descriptor,
                availability: availability,
                declaredAffordances: declared,
                claims: descriptor.selfClaims
            )
            participantRecords[descriptor.id] = record
            emit(.joined(record.view))
        }
        refreshAggregateAvailability()
    }

    private func participantRecord(for id: ParticipantID) -> ParticipantRecord {
        participantRecords[id] ?? ParticipantRecord(
            descriptor: ParticipantDescriptor(id: id, kind: .unknown),
            availability: .unknown()
        )
    }

    private func updateAvailability(
        _ availability: Availability,
        for id: ParticipantID
    ) {
        var record = participantRecord(for: id)
        let oldState = record.availability.state
        record.availability = availability
        participantRecords[id] = record
        if oldState != availability.state {
            switch availability.state {
            case .available, .degraded:
                emit(.becameAvailable(id))
            case .unavailable:
                emit(.becameUnavailable(id))
            case .unknown:
                emit(.updated(record.view))
            }
        } else {
            emit(.updated(record.view))
        }
        refreshAggregateAvailability()
    }

    private func aggregateAvailability(
        for aggregate: AggregateParticipantDescriptor
    ) -> Availability {
        guard !aggregate.members.isEmpty else {
            return .unavailable(reason: "aggregate has no members")
        }
        let availableWeight = aggregate.members.reduce(0.0) { result, member in
            isAggregateMemberAvailable(member.id)
                ? result + member.weight
                : result
        }
        let totalWeight = aggregate.members.reduce(0.0) { $0 + $1.weight }
        let availableCount = aggregate.members.filter {
            isAggregateMemberAvailable($0.id)
        }.count
        let available = evaluate(
            aggregate.rollupPolicy.availabilityRule,
            availableCount: availableCount,
            totalCount: aggregate.members.count,
            availableWeight: availableWeight,
            totalWeight: totalWeight
        )
        if available {
            return .available()
        }
        let supportsDegraded = aggregate.rollupPolicy.degradationMode
            == .partialCapability
            || aggregate.rollupPolicy.degradationMode == .bestEffort
        if availableCount > 0, supportsDegraded {
            return Availability(
                state: .degraded,
                reason: "aggregate rollup degraded"
            )
        }
        return .unavailable(reason: "aggregate rollup unavailable")
    }

    private func isAggregateMemberAvailable(_ id: ParticipantID) -> Bool {
        guard let record = participantRecords[id], !record.isBlocked else {
            return false
        }
        let stateIsAvailable = record.availability.state == .available
            || record.availability.state == .degraded
        let observationIsCurrent = record.availability.expiresAt.map {
            $0 > Date()
        } ?? true
        return stateIsAvailable && observationIsCurrent
    }

    private func evaluate(
        _ rule: RollupRule,
        availableCount: Int,
        totalCount: Int,
        availableWeight: Double,
        totalWeight: Double
    ) -> Bool {
        switch rule {
        case .all:
            return availableCount == totalCount
        case .any:
            return availableCount > 0
        case .quorum(let ratio):
            return totalCount > 0
                && Double(availableCount) / Double(totalCount) >= ratio
        case .minimumCount(let count):
            return availableCount >= count
        case .weightedThreshold(let threshold):
            return totalWeight > 0
                && availableWeight / totalWeight >= threshold
        }
    }

    private func refreshAggregateAvailability() {
        let aggregates = aggregateDescriptors.values.sorted {
            $0.id.rawValue < $1.id.rawValue
        }
        for _ in 0..<aggregates.count {
            var changed = false
            for aggregate in aggregates {
                guard var record = participantRecords[aggregate.id] else {
                    continue
                }
                let oldState = record.availability.state
                let availability = aggregateAvailability(for: aggregate)
                record.availability = availability
                participantRecords[aggregate.id] = record
                guard oldState != availability.state else {
                    continue
                }
                changed = true
                switch availability.state {
                case .available, .degraded:
                    emit(.becameAvailable(aggregate.id))
                case .unavailable:
                    emit(.becameUnavailable(aggregate.id))
                case .unknown:
                    emit(.updated(record.view))
                }
            }
            if !changed {
                break
            }
        }
    }

    private func directStep(
        message: Message,
        participantID: ParticipantID
    ) -> RoutePlanStep {
        guard let view = participantRecords[participantID]?.view else {
            return RoutePlanStep(
                kind: .reject,
                participantID: participantID,
                reasons: ["participant not found"]
            )
        }
        guard aggregateDescriptors[participantID] == nil else {
            return RoutePlanStep(
                kind: .reject,
                participantID: participantID,
                reasons: ["aggregate participants do not own execution endpoints"]
            )
        }
        guard isRoutable(view) else {
            return RoutePlanStep(
                kind: .reject,
                participantID: participantID,
                reasons: ["participant unavailable or blocked"]
            )
        }
        let supportsRepresentation = view.descriptor.representations.isEmpty
            || view.descriptor.representations.contains(message.representation)
        guard supportsRepresentation else {
            if let mediator = mediationStep(for: message, target: view) {
                return mediator
            }
            return RoutePlanStep(
                kind: .reject,
                participantID: participantID,
                reasons: ["message representation unsupported"]
            )
        }
        let affordance = selectAffordance(for: message, in: view)
        if message.intent != nil, affordance == nil {
            return RoutePlanStep(
                kind: .reject,
                participantID: participantID,
                reasons: ["required affordance is unavailable"]
            )
        }
        return RoutePlanStep(
            kind: .send,
            participantID: participantID,
            affordanceID: affordance?.id,
            deliveryOption: selectDeliveryOption(from: affordance),
            reasons: affordance == nil
                ? ["direct participant route"]
                : ["matched affordance contract"],
            risks: view.availability.state == .degraded
                ? ["participant degraded"]
                : []
        )
    }

    private func routePlan(
        message: Message,
        steps: [RoutePlanStep]
    ) -> RoutePlan {
        let requiredPolicies = Set(steps.compactMap { step -> Set<String>? in
            guard let participantID = step.participantID,
                  let affordanceID = step.affordanceID,
                  let affordance = participantRecords[participantID]?
                    .affordances.first(where: { $0.id == affordanceID }) else {
                return nil
            }
            return affordance.contract.requiredPolicies
        }.flatMap { $0 })
        let hasRejectedStep = steps.contains { $0.kind == .reject }
        let evidenceInputs = Set(steps.compactMap { step -> Set<String>? in
            guard let participantID = step.participantID,
                  let affordanceID = step.affordanceID,
                  let affordance = participantRecords[participantID]?
                    .affordances.first(where: { $0.id == affordanceID }) else {
                return nil
            }
            return affordance.evidenceIDs
        }.flatMap { $0 })

        return RoutePlan(
            messageID: message.id,
            steps: steps,
            requiredPolicies: requiredPolicies,
            policyDecision: policyDecision(
                requiredPolicies: requiredPolicies,
                hasRejectedStep: hasRejectedStep
            ),
            evidenceInputs: evidenceInputs,
            expiresAt: message.expiresAt
        )
    }

    private func policyDecision(
        requiredPolicies: Set<String>,
        hasRejectedStep: Bool
    ) -> PolicyDecision {
        if hasRejectedStep {
            return PolicyDecision(
                state: .denied,
                policyIDs: requiredPolicies,
                reasons: ["route contains rejected step"]
            )
        }
        if requiredPolicies.isEmpty {
            return PolicyDecision(
                state: .approved,
                policyIDs: [],
                reasons: ["no policy gate required"]
            )
        }
        return PolicyDecision(
            state: .requiresApproval,
            policyIDs: requiredPolicies,
            reasons: ["pre-execution policy approval required"]
        )
    }

    private func selectAffordance(
        for message: Message,
        in view: ParticipantView
    ) -> Affordance? {
        view.affordances.filter { affordance in
            guard affordance.state == .available
                    || affordance.state == .degraded else {
                return false
            }
            if let intent = message.intent, affordance.contract.id != intent {
                return false
            }
            return affordance.contract.input == message.representation
        }.sorted { lhs, rhs in
            if lhs.evidenceIDs.count == rhs.evidenceIDs.count {
                return lhs.deliveryOptions.count > rhs.deliveryOptions.count
            }
            return lhs.evidenceIDs.count > rhs.evidenceIDs.count
        }.first
    }

    private func selectDeliveryOption(
        from affordance: Affordance?
    ) -> DeliveryOption? {
        affordance?.deliveryOptions.first
            ?? DeliveryOption(semantics: .requestResponse)
    }

    private func mediationStep(
        for message: Message,
        target: ParticipantView
    ) -> RoutePlanStep? {
        let mediator = participantRecords.values
            .map(\.view)
            .first { view in
                view.affordances.contains { affordance in
                    guard let output = affordance.contract.output else {
                        return false
                    }
                    return affordance.contract.input == message.representation
                        && target.descriptor.representations.contains(output)
                        && affordance.state == .available
                }
            }
        guard let mediator else {
            return nil
        }
        let affordance = mediator.affordances.first { affordance in
            guard let output = affordance.contract.output else {
                return false
            }
            return affordance.contract.input == message.representation
                && target.descriptor.representations.contains(output)
                && affordance.state == .available
        }
        return RoutePlanStep(
            kind: .mediate,
            participantID: mediator.id,
            affordanceID: affordance?.id,
            deliveryOption: selectDeliveryOption(from: affordance),
            reasons: ["representation mediation required"],
            risks: ["mediated route changes payload representation"]
        )
    }

    private func declaredAffordances(
        for descriptor: ParticipantDescriptor,
        availability: Availability
    ) -> [Affordance] {
        descriptor.capabilityContracts.map { contract in
            Affordance(
                id: contract.id,
                ownerID: descriptor.id,
                contract: contract,
                state: availability.state == .unavailable
                    ? .unavailable
                    : .available
            )
        }
    }

    private func isRoutable(_ view: ParticipantView) -> Bool {
        guard !view.isBlocked else {
            return false
        }
        let isAvailable = view.availability.state == .available
            || view.availability.state == .degraded
        let isCurrent = view.availability.expiresAt.map { $0 > Date() } ?? true
        guard isAvailable, isCurrent else {
            return false
        }
        if let registration = localRegistrations[view.id] {
            return registration.state.isExecutable
        }
        return remoteBindings[view.id] != nil
    }

    private func validateExecutable(
        _ plan: RoutePlan,
        target: ParticipantID
    ) throws {
        if let expiresAt = plan.expiresAt, expiresAt <= Date() {
            throw SymbioRuntimeError.routeRejected("route expired before execution")
        }
        if let expiresAt = plan.policyDecision.expiresAt,
           expiresAt <= Date() {
            throw SymbioRuntimeError.policyDenied([
                "authorization decision expired before execution"
            ])
        }
        guard plan.policyDecision.policyIDs.isSuperset(
            of: plan.requiredPolicies
        ) else {
            throw SymbioRuntimeError.policyDenied([
                "authorization does not cover every required policy"
            ])
        }
        switch plan.policyDecision.state {
        case .requiresApproval:
            throw SymbioRuntimeError.policyApprovalRequired(
                plan.requiredPolicies
            )
        case .denied:
            throw SymbioRuntimeError.policyDenied(
                plan.policyDecision.reasons
            )
        case .approved:
            break
        }
        guard let step = plan.steps.first(
            where: { $0.participantID == target }
        ) else {
            throw SymbioRuntimeError.participantNotFound(target)
        }
        guard step.kind == .send else {
            throw SymbioRuntimeError.routeRejected(
                step.reasons.joined(separator: ", ")
            )
        }
    }

    private func executablePlan(
        for message: Message,
        target: ParticipantID,
        authorizer: (any PolicyAuthorizer)?
    ) async throws -> RoutePlan {
        let pending = planRoute(for: message)
        guard pending.steps.contains(
            where: { $0.participantID == target }
        ) else {
            throw SymbioRuntimeError.routeRejected(
                "route does not contain an executable target step"
            )
        }
        switch pending.policyDecision.state {
        case .approved, .denied:
            return pending
        case .requiresApproval:
            guard let authorizer else {
                throw SymbioRuntimeError.policyApprovalRequired(
                    pending.requiredPolicies
                )
            }
            let authorized = await authorize(
                pending,
                using: authorizer
            )
            guard authorized.policyDecision.state == .approved else {
                throw SymbioRuntimeError.policyDenied(
                    authorized.policyDecision.reasons
                )
            }
            let refreshed = planRoute(for: message)
            guard authorized.policyDecision.policyIDs.isSuperset(
                of: refreshed.requiredPolicies
            ) else {
                throw SymbioRuntimeError.policyDenied([
                    "route requirements changed during authorization"
                ])
            }
            return refreshed.withPolicyDecision(
                authorized.policyDecision
            )
        }
    }

    private static func validateDescriptor(
        _ descriptor: ParticipantDescriptor
    ) throws {
        let participantID = descriptor.id
        guard !participantID.rawValue.trimmingCharacters(
            in: .whitespacesAndNewlines
        ).isEmpty else {
            throw SymbioRuntimeError.invalidParticipantDescriptor(
                participantID,
                reason: "participant ID must not be empty"
            )
        }
        guard descriptor.capabilityContracts.allSatisfy({ contract in
            !contract.id.trimmingCharacters(
                in: .whitespacesAndNewlines
            ).isEmpty
                && contract.requiredPolicies.allSatisfy {
                    !$0.trimmingCharacters(
                        in: .whitespacesAndNewlines
                    ).isEmpty
                }
        }) else {
            throw SymbioRuntimeError.invalidParticipantDescriptor(
                participantID,
                reason: "capability and required policy identifiers must not be empty"
            )
        }
        let capabilityIDs = descriptor.capabilityContracts.map(\.id)
        guard Set(capabilityIDs).count == capabilityIDs.count else {
            throw SymbioRuntimeError.invalidParticipantDescriptor(
                participantID,
                reason: "capability identifiers must be unique"
            )
        }
        let contractRepresentations = descriptor.capabilityContracts.reduce(
            into: Set<MessageRepresentation>()
        ) { result, contract in
            result.insert(contract.input)
            if let output = contract.output {
                result.insert(output)
            }
        }
        let representations = descriptor.representations.union(
            contractRepresentations
        )
        guard representations.allSatisfy(isValidRepresentation) else {
            throw SymbioRuntimeError.invalidParticipantDescriptor(
                participantID,
                reason: "representations require a content type and typed payloads require a schema"
            )
        }
        guard descriptor.selfClaims.allSatisfy({ claim in
            claim.subjectID == participantID
                && claim.issuerID == participantID
                && !claim.id.trimmingCharacters(
                    in: .whitespacesAndNewlines
                ).isEmpty
                && !claim.predicate.trimmingCharacters(
                    in: .whitespacesAndNewlines
                ).isEmpty
                && claim.confidence.map {
                    $0.isFinite && (0...1).contains($0)
                } ?? true
        }) else {
            throw SymbioRuntimeError.invalidParticipantDescriptor(
                participantID,
                reason: "self claims must be well formed, self-issued, and refer to the participant"
            )
        }
    }

    private static func isValidRepresentation(
        _ representation: MessageRepresentation
    ) -> Bool {
        guard !representation.contentType.trimmingCharacters(
            in: .whitespacesAndNewlines
        ).isEmpty else {
            return false
        }
        guard representation.kind == .typedPayload else {
            return true
        }
        guard let schema = representation.schema else {
            return false
        }
        return !schema.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private func validateAggregate(
        _ aggregate: AggregateParticipantDescriptor
    ) throws {
        guard !aggregate.id.rawValue.trimmingCharacters(
            in: .whitespacesAndNewlines
        ).isEmpty else {
            throw SymbioRuntimeError.invalidAggregateDescriptor(
                aggregate.id,
                reason: "aggregate ID must not be empty"
            )
        }
        guard !aggregate.members.isEmpty else {
            throw SymbioRuntimeError.invalidAggregateDescriptor(
                aggregate.id,
                reason: "aggregate must contain at least one member"
            )
        }
        let memberIDs = aggregate.members.map(\.id)
        guard Set(memberIDs).count == memberIDs.count,
              !memberIDs.contains(aggregate.id) else {
            throw SymbioRuntimeError.invalidAggregateDescriptor(
                aggregate.id,
                reason: "aggregate members must be unique and cannot include the aggregate itself"
            )
        }
        guard aggregate.members.allSatisfy({
            $0.weight.isFinite && $0.weight > 0
        }) else {
            throw SymbioRuntimeError.invalidAggregateDescriptor(
                aggregate.id,
                reason: "aggregate member weights must be finite and greater than zero"
            )
        }
        try validateRollupRule(
            aggregate.rollupPolicy.availabilityRule,
            memberCount: aggregate.members.count,
            aggregateID: aggregate.id
        )
        try validateAggregateGraph(adding: aggregate)
    }

    private func validateAggregateGraph(
        adding aggregate: AggregateParticipantDescriptor
    ) throws {
        var graph = aggregateDescriptors
        graph[aggregate.id] = aggregate
        var visiting: Set<ParticipantID> = []
        var visited: Set<ParticipantID> = []

        func containsCycle(from id: ParticipantID) -> Bool {
            if visiting.contains(id) {
                return true
            }
            if visited.contains(id) {
                return false
            }
            visiting.insert(id)
            for member in graph[id]?.members ?? []
                where graph[member.id] != nil {
                if containsCycle(from: member.id) {
                    return true
                }
            }
            visiting.remove(id)
            visited.insert(id)
            return false
        }

        for id in graph.keys {
            if containsCycle(from: id) {
                throw SymbioRuntimeError.invalidAggregateDescriptor(
                    aggregate.id,
                    reason: "aggregate membership graph must be acyclic"
                )
            }
        }
    }

    private func validateRollupRule(
        _ rule: RollupRule,
        memberCount: Int,
        aggregateID: ParticipantID
    ) throws {
        let isValid: Bool
        switch rule {
        case .all, .any:
            isValid = true
        case .quorum(let ratio), .weightedThreshold(let ratio):
            isValid = ratio.isFinite && ratio > 0 && ratio <= 1
        case .minimumCount(let count):
            isValid = count > 0 && count <= memberCount
        }
        guard isValid else {
            throw SymbioRuntimeError.invalidAggregateDescriptor(
                aggregateID,
                reason: "rollup thresholds must be finite and within the aggregate member range"
            )
        }
    }

    private func emit(_ change: SymbioRuntimeChange) {
        for subscriber in Array(changeSubscribers.values) {
            switch subscriber.continuation.yield(change) {
            case .enqueued:
                continue
            case .dropped:
                subscriber.continuation.finish(
                    throwing: SymbioRuntimeError.changeSubscriberOverflow
                )
                changeSubscribers.removeValue(forKey: subscriber.id)
            case .terminated:
                changeSubscribers.removeValue(forKey: subscriber.id)
            @unknown default:
                subscriber.continuation.finish(
                    throwing: SymbioRuntimeError.changeSubscriberOverflow
                )
                changeSubscribers.removeValue(forKey: subscriber.id)
            }
        }
    }

    private func removeChangeSubscriber(_ id: String) {
        changeSubscribers.removeValue(forKey: id)
    }

    private func finishChangeSubscribers(
        throwing error: (any Error)? = nil
    ) {
        let subscribers = Array(changeSubscribers.values)
        changeSubscribers.removeAll()
        for subscriber in subscribers {
            if let error {
                subscriber.continuation.finish(throwing: error)
            } else {
                subscriber.continuation.finish()
            }
        }
    }
}
