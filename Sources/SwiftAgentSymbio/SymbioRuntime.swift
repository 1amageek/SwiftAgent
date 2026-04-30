//
//  SymbioRuntime.swift
//  SwiftAgentSymbio
//

import Foundation
import SwiftAgent
import Distributed

public enum SymbioRuntimeChange: Sendable {
    case joined(ParticipantView)
    case left(ParticipantID)
    case updated(ParticipantView)
    case becameAvailable(ParticipantID)
    case becameUnavailable(ParticipantID)
}

public actor SymbioRuntime {
    public let actorSystem: SymbioActorSystem

    private let transport: any SymbioTransport
    private var participantRecords: [ParticipantID: ParticipantRecord] = [:]
    private var aggregateDescriptors: [ParticipantID: AggregateParticipantDescriptor] = [:]
    private var localAgentIDs: Set<ParticipantID> = []
    private var localAgentRefs: [ParticipantID: any DistributedActor] = [:]
    private var registeredMethods: [ParticipantID: [String]] = [:]
    private var changeContinuation: AsyncStream<SymbioRuntimeChange>.Continuation?
    private var _changes: AsyncStream<SymbioRuntimeChange>?
    private var monitorTask: Task<Void, Never>?

    public init(
        actorSystem: SymbioActorSystem,
        transport: any SymbioTransport = LocalOnlySymbioTransport()
    ) {
        self.actorSystem = actorSystem
        self.transport = transport
    }

    public func start() async throws {
        if monitorTask != nil {
            return
        }
        await transport.setInvocationHandler { [actorSystem] envelope, senderID in
            await actorSystem.handleIncomingInvocation(envelope, from: senderID.rawValue)
        }
        try await transport.start()
        startMonitoring()
    }

    public func stop() async throws {
        monitorTask?.cancel()
        monitorTask = nil
        defer {
            changeContinuation?.finish()
            changeContinuation = nil
            _changes = nil
        }

        for agentID in localAgentIDs {
            if let agent = localAgentRefs[agentID] as? Terminatable {
                await agent.terminate()
            }

            if let methods = registeredMethods[agentID] {
                for method in methods {
                    actorSystem.unregisterMethod(method)
                }
            }

            let address = try Address(hexString: agentID.rawValue)
            actorSystem.resignID(address)
            changeContinuation?.yield(.left(agentID))
        }

        localAgentIDs.removeAll()
        localAgentRefs.removeAll()
        registeredMethods.removeAll()
        participantRecords.removeAll()
        aggregateDescriptors.removeAll()

        await transport.removeInvocationHandler()
        try await transport.shutdown()
    }

    public var participantViews: [ParticipantView] {
        participantRecords.values
            .map { $0.view }
            .sorted { $0.id.rawValue < $1.id.rawValue }
    }

    public var availableParticipants: [ParticipantView] {
        participantViews.filter { isRoutable($0) }
    }

    public func participantView(for id: ParticipantID) -> ParticipantView? {
        participantRecords[id]?.view
    }

    public func register(
        _ descriptor: ParticipantDescriptor,
        availability: Availability = .available()
    ) {
        let declaredAffordances = declaredAffordances(for: descriptor, availability: availability)
        if var record = participantRecords[descriptor.id] {
            record.descriptor = descriptor
            record.availability = availability
            record.affordances = mergeAffordances(record.affordances, with: declaredAffordances)
            record.claims = descriptor.selfClaims
            participantRecords[descriptor.id] = record
            changeContinuation?.yield(.updated(record.view))
        } else {
            let record = ParticipantRecord(
                descriptor: descriptor,
                availability: availability,
                affordances: declaredAffordances,
                claims: descriptor.selfClaims
            )
            participantRecords[descriptor.id] = record
            changeContinuation?.yield(.joined(record.view))
        }
        refreshAggregateAvailability()
    }

    public func register(_ aggregate: AggregateParticipantDescriptor) {
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
        register(descriptor, availability: aggregateAvailability(for: aggregate))
    }

    public func observe(_ evidence: Evidence) {
        var record = participantRecord(for: evidence.subjectID)
        record.evidence.append(evidence)
        participantRecords[evidence.subjectID] = record
        changeContinuation?.yield(.updated(record.view))
    }

    public func observe(_ affordance: Affordance) {
        var record = participantRecord(for: affordance.ownerID)
        record.affordances.removeAll { $0.id == affordance.id }
        record.affordances.append(affordance)
        participantRecords[affordance.ownerID] = record
        changeContinuation?.yield(.updated(record.view))
    }

    public func observe(_ trustView: TrustView) {
        var record = participantRecord(for: trustView.subjectID)
        record.trustViews.removeAll { $0.issuerID == trustView.issuerID }
        record.trustViews.append(trustView)
        participantRecords[trustView.subjectID] = record
        changeContinuation?.yield(.updated(record.view))
    }

    public func updateAvailability(
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
                changeContinuation?.yield(.becameAvailable(id))
            case .unavailable:
                changeContinuation?.yield(.becameUnavailable(id))
            case .unknown:
                changeContinuation?.yield(.updated(record.view))
            }
        } else {
            changeContinuation?.yield(.updated(record.view))
        }
        refreshAggregateAvailability()
    }

    public func block(_ id: ParticipantID, reason: String? = nil) {
        var record = participantRecord(for: id)
        record.isBlocked = true
        if let reason {
            record.constraints.append(reason)
        }
        participantRecords[id] = record
        changeContinuation?.yield(.updated(record.view))
        refreshAggregateAvailability()
    }

    public func forget(_ id: ParticipantID) throws {
        guard !localAgentIDs.contains(id) else {
            throw SymbioRuntimeError.cannotForgetLocal(id)
        }
        participantRecords.removeValue(forKey: id)
        changeContinuation?.yield(.left(id))
        refreshAggregateAvailability()
    }

    public func planRoute(for message: Message) -> RoutePlan {
        switch message.addressing {
        case .direct(let participantID):
            return routePlan(
                message: message,
                steps: [directStep(message: message, participantID: participantID)]
            )
        case .group(let participantIDs):
            let steps = participantIDs
                .sorted { $0.rawValue < $1.rawValue }
                .map { directStep(message: message, participantID: $0) }
            return routePlan(message: message, steps: steps)
        case .open:
            return routePlan(
                message: message,
                steps: [
                    RoutePlanStep(kind: .broadcast, reasons: ["open message"])
                ]
            )
        }
    }

    public func authorize(
        _ plan: RoutePlan,
        using authorizer: any PolicyAuthorizer
    ) async -> RoutePlan {
        guard !plan.requiredPolicies.isEmpty else {
            return plan.withPolicyDecision(PolicyDecision(
                state: plan.steps.contains { $0.kind == .reject } ? .denied : .approved,
                policyIDs: [],
                reasons: plan.steps.contains { $0.kind == .reject } ? ["route contains rejected step"] : ["no policy gate required"]
            ))
        }
        let decision = await authorizer.authorize(plan.policyRequest())
        return plan.withPolicyDecision(decision)
    }

    @discardableResult
    public func send<S: Sendable & Codable>(
        _ signal: S,
        to participantID: ParticipantID,
        perception: String,
        senderID: ParticipantID = ParticipantID(rawValue: "local"),
        authorizer: (any PolicyAuthorizer)? = nil,
        timeout: Duration = .seconds(30)
    ) async throws -> Data? {
        let representation = MessageRepresentation.typedPayload(schema: perception)
        let data = try JSONEncoder().encode(signal)
        let message = Message(
            senderID: senderID,
            addressing: .direct(participantID),
            representation: representation,
            payload: data,
            intent: "\(AgentCapabilityNamespace.perception).\(perception)"
        )
        let plan = try await executablePlan(for: message, target: participantID, authorizer: authorizer)
        try validateExecutable(plan, target: participantID)

        let capability = "\(AgentCapabilityNamespace.perception).\(perception)"
        if localAgentIDs.contains(participantID),
           let agent = localAgentRefs[participantID] as? any Communicable {
            do {
                let response = try await agent.receive(data, perception: perception)
                observe(Evidence(subjectID: participantID, kind: .successfulInvocation))
                return response
            } catch {
                observe(Evidence(
                    subjectID: participantID,
                    kind: .failedInvocation,
                    message: error.localizedDescription
                ))
                throw error
            }
        }

        let result = try await transport.invoke(
            SymbioInvocationEnvelope(capability: capability, arguments: data),
            on: participantID,
            timeout: timeout
        )
        return try handleInvocationReply(result, participantID: participantID)
    }

    public func invoke(
        _ capability: String,
        on participantID: ParticipantID,
        with arguments: Data,
        senderID: ParticipantID = ParticipantID(rawValue: "local"),
        authorizer: (any PolicyAuthorizer)? = nil,
        timeout: Duration = .seconds(30)
    ) async throws -> Data {
        let representation = MessageRepresentation.typedPayload(schema: capability)
        let message = Message(
            senderID: senderID,
            addressing: .direct(participantID),
            representation: representation,
            payload: arguments,
            intent: capability
        )
        let plan = try await executablePlan(for: message, target: participantID, authorizer: authorizer)
        try validateExecutable(plan, target: participantID)

        if localAgentIDs.contains(participantID),
           let agent = localAgentRefs[participantID] as? any CapabilityProviding {
            do {
                let response = try await agent.invokeCapability(arguments, capability: capability)
                observe(Evidence(subjectID: participantID, kind: .successfulInvocation))
                return response
            } catch {
                observe(Evidence(
                    subjectID: participantID,
                    kind: .failedInvocation,
                    message: error.localizedDescription
                ))
                throw error
            }
        }

        let result = try await transport.invoke(
            SymbioInvocationEnvelope(capability: capability, arguments: arguments),
            on: participantID,
            timeout: timeout
        )
        guard let data = try handleInvocationReply(result, participantID: participantID) else {
            throw SymbioRuntimeError.invocationFailed("Missing result data")
        }
        return data
    }

    @discardableResult
    public func spawn<A: Communicable>(
        _ factory: @escaping () async throws -> A
    ) async throws -> ParticipantView {
        let agent = try await factory()
        let agentID = ParticipantID(rawValue: agent.id.hexString)
        let descriptor = participantDescriptor(for: agent)
        localAgentIDs.insert(agentID)
        localAgentRefs[agentID] = agent

        var methods: [String] = []
        for perception in agent.perceptions {
            let methodName = "\(AgentCapabilityNamespace.perception).\(perception.identifier)"
            actorSystem.registerMethod(methodName, for: agent.id)
            methods.append(methodName)
        }
        if let provider = agent as? any CapabilityProviding {
            for capability in provider.providedCapabilities {
                actorSystem.registerMethod(capability, for: agent.id)
                methods.append(capability)
            }
        }
        registeredMethods[agentID] = methods
        register(descriptor, availability: .available())
        return participantRecords[agentID]?.view ?? ParticipantRecord(descriptor: descriptor).view
    }

    public func terminate(_ participantID: ParticipantID) async throws {
        guard localAgentIDs.contains(participantID) else {
            throw SymbioRuntimeError.cannotTerminateRemote(participantID)
        }
        try await terminateLocalAgent(participantID)
        participantRecords.removeValue(forKey: participantID)
        changeContinuation?.yield(.left(participantID))
        refreshAggregateAvailability()
    }

    public var changes: AsyncStream<SymbioRuntimeChange> {
        if let existing = _changes {
            return existing
        }
        let (stream, continuation) = AsyncStream<SymbioRuntimeChange>.makeStream()
        _changes = stream
        changeContinuation = continuation
        return stream
    }

    private func startMonitoring() {
        monitorTask = Task { [weak self] in
            guard let self else { return }
            for await event in self.transport.events {
                guard !Task.isCancelled else { break }
                await self.handleTransportEvent(event)
            }
        }
    }

    private func handleTransportEvent(_ event: SymbioTransportEvent) {
        switch event {
        case .peerDiscovered(let descriptor):
            register(descriptor, availability: .available())
        case .peerConnected(let peerID):
            updateAvailability(.available(), for: peerID)
        case .peerLost(let peerID),
             .peerDisconnected(let peerID):
            updateAvailability(.unavailable(reason: "transport disconnected"), for: peerID)
        case .error:
            break
        }
    }

    private func participantRecord(for id: ParticipantID) -> ParticipantRecord {
        if let record = participantRecords[id] {
            return record
        }
        return ParticipantRecord(
            descriptor: ParticipantDescriptor(id: id, kind: .unknown),
            availability: .unknown()
        )
    }

    private func aggregateAvailability(for aggregate: AggregateParticipantDescriptor) -> Availability {
        guard !aggregate.members.isEmpty else {
            return .unavailable(reason: "aggregate has no members")
        }
        let availableWeights = aggregate.members.reduce(0.0) { partial, member in
            if isAggregateMemberAvailable(member.id) {
                return partial + member.weight
            }
            return partial
        }
        let totalWeight = aggregate.members.reduce(0.0) { $0 + $1.weight }
        let availableCount = aggregate.members.filter { member in
            isAggregateMemberAvailable(member.id)
        }.count
        let isAvailable = evaluate(
            aggregate.rollupPolicy.availabilityRule,
            availableCount: availableCount,
            totalCount: aggregate.members.count,
            availableWeight: availableWeights,
            totalWeight: totalWeight
        )
        if isAvailable {
            return .available()
        }
        if availableCount > 0,
           (
            aggregate.rollupPolicy.degradationMode == .partialCapability
                || aggregate.rollupPolicy.degradationMode == .bestEffort
           ) {
            return Availability(state: .degraded, reason: "aggregate rollup degraded")
        }
        return .unavailable(reason: "aggregate rollup unavailable")
    }

    private func isAggregateMemberAvailable(_ id: ParticipantID) -> Bool {
        guard let record = participantRecords[id],
              !record.isBlocked else {
            return false
        }
        return record.availability.state == .available || record.availability.state == .degraded
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
            guard totalCount > 0 else { return false }
            return Double(availableCount) / Double(totalCount) >= ratio
        case .minimumCount(let count):
            return availableCount >= count
        case .weightedThreshold(let threshold):
            guard totalWeight > 0 else { return false }
            return availableWeight / totalWeight >= threshold
        }
    }

    private func refreshAggregateAvailability() {
        for aggregate in aggregateDescriptors.values {
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
            switch availability.state {
            case .available, .degraded:
                changeContinuation?.yield(.becameAvailable(aggregate.id))
            case .unavailable:
                changeContinuation?.yield(.becameUnavailable(aggregate.id))
            case .unknown:
                changeContinuation?.yield(.updated(record.view))
            }
        }
    }

    private func directStep(
        message: Message,
        participantID: ParticipantID
    ) -> RoutePlanStep {
        guard let view = participantRecords[participantID]?.view else {
            return RoutePlanStep(kind: .reject, participantID: participantID, reasons: ["participant not found"])
        }
        guard isRoutable(view) else {
            return RoutePlanStep(kind: .reject, participantID: participantID, reasons: ["participant unavailable or blocked"])
        }
        guard view.descriptor.representations.isEmpty || view.descriptor.representations.contains(message.representation) else {
            if let mediator = mediationStep(for: message, target: view) {
                return mediator
            }
            return RoutePlanStep(kind: .reject, participantID: participantID, reasons: ["message representation unsupported"])
        }
        let selectedAffordance = selectAffordance(for: message, in: view)
        if message.intent != nil, selectedAffordance == nil {
            return RoutePlanStep(
                kind: .reject,
                participantID: participantID,
                reasons: ["required affordance is unavailable"]
            )
        }
        let deliveryOption = selectDeliveryOption(from: selectedAffordance)
        return RoutePlanStep(
            kind: .send,
            participantID: participantID,
            affordanceID: selectedAffordance?.id,
            deliveryOption: deliveryOption,
            reasons: selectedAffordance == nil ? ["direct participant route"] : ["matched affordance contract"],
            risks: view.availability.state == .degraded ? ["participant degraded"] : []
        )
    }

    private func routePlan(
        message: Message,
        steps: [RoutePlanStep]
    ) -> RoutePlan {
        let requiredPolicies = Set(steps.compactMap { step -> Set<String>? in
            guard let participantID = step.participantID,
                  let affordanceID = step.affordanceID,
                  let affordance = participantRecords[participantID]?.affordances.first(where: { $0.id == affordanceID }) else {
                return nil
            }
            return affordance.contract.requiredPolicies
        }.flatMap { $0 })
        let hasRejectedStep = steps.contains { $0.kind == .reject }
        let decision = policyDecision(requiredPolicies: requiredPolicies, hasRejectedStep: hasRejectedStep)
        let evidenceInputs = Set(steps.compactMap { step -> Set<String>? in
            guard let participantID = step.participantID,
                  let affordanceID = step.affordanceID,
                  let affordance = participantRecords[participantID]?.affordances.first(where: { $0.id == affordanceID }) else {
                return nil
            }
            return affordance.evidenceIDs
        }.flatMap { $0 })

        return RoutePlan(
            messageID: message.id,
            steps: steps,
            requiredPolicies: requiredPolicies,
            policyDecision: decision,
            evidenceInputs: evidenceInputs,
            expiresAt: message.expiresAt
        )
    }

    private func policyDecision(
        requiredPolicies: Set<String>,
        hasRejectedStep: Bool
    ) -> PolicyDecision {
        if hasRejectedStep {
            return PolicyDecision(state: .denied, policyIDs: requiredPolicies, reasons: ["route contains rejected step"])
        }
        if requiredPolicies.isEmpty {
            return PolicyDecision(state: .approved, policyIDs: [], reasons: ["no policy gate required"])
        }
        return PolicyDecision(state: .requiresApproval, policyIDs: requiredPolicies, reasons: ["pre-execution policy approval required"])
    }

    private func selectAffordance(
        for message: Message,
        in view: ParticipantView
    ) -> Affordance? {
        view.affordances.filter { affordance in
            guard affordance.state == .available || affordance.state == .degraded else {
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

    private func selectDeliveryOption(from affordance: Affordance?) -> DeliveryOption? {
        guard let affordance else {
            return DeliveryOption(semantics: .requestResponse)
        }
        return affordance.deliveryOptions.first ?? DeliveryOption(semantics: .requestResponse)
    }

    private func mediationStep(
        for message: Message,
        target: ParticipantView
    ) -> RoutePlanStep? {
        let mediator = participantRecords.values
            .map { $0.view }
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
                state: availability.state == .unavailable ? .unavailable : .available
            )
        }
    }

    private func mergeAffordances(
        _ current: [Affordance],
        with incoming: [Affordance]
    ) -> [Affordance] {
        var merged = Dictionary(uniqueKeysWithValues: current.map { ($0.id, $0) })
        for affordance in incoming {
            if let existing = merged[affordance.id] {
                merged[affordance.id] = mergeAffordance(existing, with: affordance)
            } else {
                merged[affordance.id] = affordance
            }
        }
        return merged.values.sorted { $0.id < $1.id }
    }

    private func mergeAffordance(_ current: Affordance, with incoming: Affordance) -> Affordance {
        Affordance(
            id: incoming.id,
            ownerID: incoming.ownerID,
            contract: incoming.contract,
            state: mergedAffordanceState(current.state, incoming.state),
            deliveryOptions: mergeDeliveryOptions(current.deliveryOptions, incoming.deliveryOptions),
            evidenceIDs: current.evidenceIDs.union(incoming.evidenceIDs),
            metadata: current.metadata.merging(incoming.metadata) { _, incoming in incoming }
        )
    }

    private func mergedAffordanceState(_ current: AffordanceState, _ incoming: AffordanceState) -> AffordanceState {
        if current == .unavailable || incoming == .unavailable {
            return .unavailable
        }
        if current == .degraded || incoming == .degraded {
            return .degraded
        }
        if current == .unknown || incoming == .unknown {
            return .unknown
        }
        return .available
    }

    private func mergeDeliveryOptions(_ current: [DeliveryOption], _ incoming: [DeliveryOption]) -> [DeliveryOption] {
        var merged = Dictionary(uniqueKeysWithValues: current.map { ($0.id, $0) })
        for option in incoming {
            merged[option.id] = option
        }
        return merged.values.sorted { $0.id < $1.id }
    }

    private func isRoutable(_ view: ParticipantView) -> Bool {
        guard !view.isBlocked else { return false }
        return view.availability.state == .available || view.availability.state == .degraded
    }

    private func validateExecutable(_ plan: RoutePlan, target: ParticipantID) throws {
        if plan.policyDecision.state != .approved {
            switch plan.policyDecision.state {
            case .requiresApproval:
                throw SymbioRuntimeError.policyApprovalRequired(plan.requiredPolicies)
            case .denied:
                throw SymbioRuntimeError.policyDenied(plan.policyDecision.reasons)
            case .approved:
                break
            }
        }
        guard let step = plan.steps.first(where: { $0.participantID == target }) else {
            throw SymbioRuntimeError.participantNotFound(target)
        }
        guard step.kind == .send else {
            throw SymbioRuntimeError.routeRejected(step.reasons.joined(separator: ", "))
        }
    }

    private func executablePlan(
        for message: Message,
        target: ParticipantID,
        authorizer: (any PolicyAuthorizer)?
    ) async throws -> RoutePlan {
        let pendingPlan = planRoute(for: message)
        guard pendingPlan.steps.contains(where: { $0.participantID == target }) else {
            throw SymbioRuntimeError.routeRejected("route does not contain an executable target step")
        }
        switch pendingPlan.policyDecision.state {
        case .approved, .denied:
            return pendingPlan
        case .requiresApproval:
            guard let authorizer else {
                throw SymbioRuntimeError.policyApprovalRequired(pendingPlan.requiredPolicies)
            }
            let authorizedPlan = await authorize(pendingPlan, using: authorizer)
            guard authorizedPlan.policyDecision.state == .approved else {
                throw SymbioRuntimeError.policyDenied(authorizedPlan.policyDecision.reasons)
            }
            return authorizedPlan
        }
    }

    private func handleInvocationReply(
        _ result: SymbioInvocationReply,
        participantID: ParticipantID
    ) throws -> Data? {
        if result.success {
            observe(Evidence(subjectID: participantID, kind: .successfulInvocation))
            return result.result
        }
        let message = result.failure?.message ?? "Unknown error"
        observe(Evidence(subjectID: participantID, kind: .failedInvocation, message: message))
        throw SymbioRuntimeError.invocationFailed(message)
    }

    private func terminateLocalAgent(_ agentID: ParticipantID) async throws {
        guard localAgentIDs.contains(agentID) else {
            throw SymbioRuntimeError.participantNotFound(agentID)
        }
        if let agent = localAgentRefs[agentID] as? Terminatable {
            await agent.terminate()
        }
        if let methods = registeredMethods[agentID] {
            for method in methods {
                actorSystem.unregisterMethod(method)
            }
        }
        registeredMethods.removeValue(forKey: agentID)
        let address = try Address(hexString: agentID.rawValue)
        actorSystem.resignID(address)
        localAgentIDs.remove(agentID)
        localAgentRefs.removeValue(forKey: agentID)
    }

    private func participantDescriptor<A: Communicable>(for agent: A) -> ParticipantDescriptor {
        let id = ParticipantID(rawValue: agent.id.hexString)
        let perceptionContracts = agent.perceptions.map { perception in
            CapabilityContract(
                id: "\(AgentCapabilityNamespace.perception).\(perception.identifier)",
                purpose: "receive signal",
                input: .typedPayload(schema: perception.identifier),
                sideEffectLevel: .localState
            )
        }
        let actionContracts = (agent as? any CapabilityProviding)?.providedCapabilities.map { capability in
            CapabilityContract(
                id: capability,
                purpose: "invoke capability",
                input: .typedPayload(schema: capability),
                sideEffectLevel: .network
            )
        } ?? []
        return ParticipantDescriptor(
            id: id,
            kind: .agent,
            representations: Set(perceptionContracts.map(\.input) + actionContracts.map(\.input) + [.naturalLanguage()]),
            capabilityContracts: Set(perceptionContracts + actionContracts),
            selfClaims: perceptionContracts.map { contract in
                Claim(subjectID: id, predicate: "symbio.affordance", object: contract.id, issuerID: id)
            } + actionContracts.map { contract in
                Claim(subjectID: id, predicate: "symbio.affordance", object: contract.id, issuerID: id)
            },
            metadata: ["location": "local"]
        )
    }
}

public enum SymbioRuntimeError: Error, LocalizedError, Sendable {
    case participantUnavailable(ParticipantID)
    case participantBlocked(ParticipantID)
    case participantNotFound(ParticipantID)
    case policyApprovalRequired(Set<String>)
    case policyDenied([String])
    case routeRejected(String)
    case invocationFailed(String)
    case cannotTerminateRemote(ParticipantID)
    case cannotForgetLocal(ParticipantID)

    public var errorDescription: String? {
        switch self {
        case .participantUnavailable(let id):
            return "Participant '\(id.rawValue)' is not available"
        case .participantBlocked(let id):
            return "Participant '\(id.rawValue)' is blocked in this local runtime view"
        case .participantNotFound(let id):
            return "Participant '\(id.rawValue)' was not found in this runtime view"
        case .policyApprovalRequired(let policies):
            return "Policy approval is required: \(policies.sorted().joined(separator: ", "))"
        case .policyDenied(let reasons):
            return "Policy denied: \(reasons.joined(separator: ", "))"
        case .routeRejected(let reason):
            return "Route rejected: \(reason)"
        case .invocationFailed(let message):
            return "Invocation failed: \(message)"
        case .cannotTerminateRemote(let id):
            return "Cannot terminate remote participant '\(id.rawValue)'"
        case .cannotForgetLocal(let id):
            return "Cannot forget local participant '\(id.rawValue)'"
        }
    }
}
