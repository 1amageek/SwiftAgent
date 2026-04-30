import Testing
import Foundation
@testable import SwiftAgentSymbio

@Suite("Symbio participant model")
struct SymbioParticipantModelTests {
    @Test
    func participantViewRecordsAffordanceAndEvidence() async {
        let actorSystem = SymbioActorSystem()
        let runtime = SymbioRuntime(actorSystem: actorSystem)
        let participantID = ParticipantID(rawValue: "robot.arm.1")
        let representation = MessageRepresentation.typedPayload(schema: "robot.motion.plan")
        let contract = CapabilityContract(
            id: "robot.motion.execute",
            input: representation,
            sideEffectLevel: .physical,
            requiredPolicies: ["physical.motion.approval"]
        )
        let descriptor = ParticipantDescriptor(
            id: participantID,
            displayName: "Arm 1",
            kind: .robot,
            representations: [representation],
            capabilityContracts: [contract]
        )

        await runtime.register(descriptor)
        let evidence = Evidence(
            subjectID: participantID,
            kind: .observation,
            message: "motion envelope observed"
        )
        await runtime.observe(evidence)

        let view = await runtime.participantView(for: participantID)
        #expect(view?.descriptor.id == participantID)
        #expect(view?.affordances.map(\.contract.id) == ["robot.motion.execute"])
        #expect(view?.evidence.map(\.id) == [evidence.id])
    }

    @Test
    func directRouteRequiresPolicyForPhysicalAffordance() async {
        let actorSystem = SymbioActorSystem()
        let runtime = SymbioRuntime(actorSystem: actorSystem)
        let participantID = ParticipantID(rawValue: "matter.lock.front")
        let representation = MessageRepresentation.typedPayload(schema: "matter.lock.command")
        let contract = CapabilityContract(
            id: "matter.lock.setState",
            input: representation,
            sideEffectLevel: .physical,
            requiredPolicies: ["home.lock.approval"]
        )
        let delivery = DeliveryOption(
            semantics: .requestResponse,
            maximumLatency: 0.5,
            expiry: 2
        )
        let affordance = Affordance(
            ownerID: participantID,
            contract: contract,
            deliveryOptions: [delivery],
            evidenceIDs: ["evidence.lock.online"]
        )
        let descriptor = ParticipantDescriptor(
            id: participantID,
            kind: .device,
            representations: [representation],
            capabilityContracts: [contract]
        )
        let message = Message(
            senderID: "planner",
            addressing: .direct(participantID),
            representation: representation,
            payload: Data(),
            intent: "matter.lock.setState"
        )

        await runtime.register(descriptor)
        await runtime.observe(affordance)

        let plan = await runtime.planRoute(for: message)
        #expect(plan.steps.first?.kind == .send)
        #expect(plan.requiredPolicies == ["home.lock.approval"])
        #expect(plan.policyDecision.state == .requiresApproval)
        #expect(plan.evidenceInputs == ["evidence.lock.online"])
        #expect(plan.steps.first?.deliveryOption?.semantics == .requestResponse)
    }

    @Test
    func descriptorRefreshPreservesObservedAffordanceDetails() async {
        let actorSystem = SymbioActorSystem()
        let runtime = SymbioRuntime(actorSystem: actorSystem)
        let participantID = ParticipantID(rawValue: "robot.arm.1")
        let representation = MessageRepresentation.typedPayload(schema: "robot.motion.plan")
        let contract = CapabilityContract(
            id: "robot.motion.execute",
            input: representation,
            sideEffectLevel: .physical,
            requiredPolicies: ["physical.motion.approval"]
        )
        let descriptor = ParticipantDescriptor(
            id: participantID,
            kind: .robot,
            representations: [representation],
            capabilityContracts: [contract]
        )
        let delivery = DeliveryOption(semantics: .requestResponse, maximumLatency: 0.1)
        let observed = Affordance(
            id: contract.id,
            ownerID: participantID,
            contract: contract,
            state: .degraded,
            deliveryOptions: [delivery],
            evidenceIDs: ["evidence.motion"]
        )

        await runtime.register(descriptor)
        await runtime.observe(observed)
        await runtime.register(descriptor)

        let affordance = await runtime.participantView(for: participantID)?.affordances.first
        #expect(affordance?.state == .degraded)
        #expect(affordance?.deliveryOptions.map(\.id) == [delivery.id])
        #expect(affordance?.evidenceIDs == ["evidence.motion"])
    }

    @Test
    func unsupportedRepresentationCanRouteThroughMediator() async {
        let actorSystem = SymbioActorSystem()
        let runtime = SymbioRuntime(actorSystem: actorSystem)
        let senderID = ParticipantID(rawValue: "operator")
        let targetID = ParticipantID(rawValue: "drone.1")
        let mediatorID = ParticipantID(rawValue: "translator.1")
        let language = MessageRepresentation.naturalLanguage()
        let command = MessageRepresentation.typedPayload(schema: "drone.command")
        let translation = CapabilityContract(
            id: "message.translate.droneCommand",
            input: language,
            output: command,
            sideEffectLevel: .none
        )

        await runtime.register(ParticipantDescriptor(
            id: targetID,
            kind: .robot,
            representations: [command]
        ))
        await runtime.register(ParticipantDescriptor(
            id: mediatorID,
            kind: .agent,
            representations: [language, command],
            capabilityContracts: [translation]
        ))

        let message = Message(
            senderID: senderID,
            addressing: .direct(targetID),
            representation: language,
            payload: Data()
        )

        let plan = await runtime.planRoute(for: message)
        #expect(plan.steps.first?.kind == .mediate)
        #expect(plan.steps.first?.participantID == mediatorID)
        #expect(plan.policyDecision.state == .approved)
    }

    @Test
    func aggregateDescriptorCarriesRollupPolicy() {
        let descriptor = AggregateParticipantDescriptor(
            id: "swarm.alpha",
            displayName: "Swarm Alpha",
            kind: .swarm,
            members: [
                AggregateMember(id: "drone.1", role: "scout"),
                AggregateMember(id: "drone.2", role: "scout"),
                AggregateMember(id: "drone.3", role: "relay")
            ],
            rollupPolicy: RollupPolicy(
                availabilityRule: .quorum(0.66),
                evidenceRule: .minimumCount(2),
                degradationMode: .partialCapability
            )
        )

        #expect(descriptor.members.count == 3)
        #expect(descriptor.rollupPolicy.availabilityRule == .quorum(0.66))
        #expect(descriptor.rollupPolicy.evidenceRule == .minimumCount(2))
    }

    @Test
    func aggregateAvailabilityRollsUpMemberState() async {
        let actorSystem = SymbioActorSystem()
        let runtime = SymbioRuntime(actorSystem: actorSystem)

        await runtime.register(ParticipantDescriptor(id: "drone.1", kind: .robot))
        await runtime.register(ParticipantDescriptor(id: "drone.2", kind: .robot))
        await runtime.register(
            ParticipantDescriptor(id: "drone.3", kind: .robot),
            availability: .unavailable(reason: "battery")
        )
        await runtime.register(AggregateParticipantDescriptor(
            id: "swarm.alpha",
            kind: .swarm,
            members: [
                AggregateMember(id: "drone.1"),
                AggregateMember(id: "drone.2"),
                AggregateMember(id: "drone.3")
            ],
            rollupPolicy: RollupPolicy(
                availabilityRule: .quorum(0.66),
                evidenceRule: .minimumCount(2),
                degradationMode: .partialCapability
            )
        ))

        var view = await runtime.participantView(for: "swarm.alpha")
        #expect(view?.availability.state == .available)

        await runtime.updateAvailability(.unavailable(reason: "lost"), for: "drone.2")
        view = await runtime.participantView(for: "swarm.alpha")
        #expect(view?.availability.state == .degraded)

        let changes = await runtime.changes
        var iterator = changes.makeAsyncIterator()
        await runtime.block("drone.1", reason: "operator blocked")
        _ = await iterator.next()
        let aggregateEvent = await iterator.next()

        view = await runtime.participantView(for: "swarm.alpha")
        #expect(view?.availability.state == .unavailable)
        guard case .becameUnavailable(let aggregateID) = aggregateEvent,
              aggregateID == "swarm.alpha" else {
            Issue.record("expected aggregate unavailable event")
            return
        }
    }

    @Test
    func authorizerApprovesPreExecutionPolicyGate() async {
        let actorSystem = SymbioActorSystem()
        let runtime = SymbioRuntime(actorSystem: actorSystem)
        let participantID = ParticipantID(rawValue: "robot.kicker")
        let representation = MessageRepresentation.typedPayload(schema: "robot.kick.command")
        let contract = CapabilityContract(
            id: "robot.kick",
            input: representation,
            sideEffectLevel: .physical,
            requiredPolicies: ["field.motion.approval"]
        )
        await runtime.register(ParticipantDescriptor(
            id: participantID,
            kind: .robot,
            representations: [representation],
            capabilityContracts: [contract]
        ))

        let message = Message(
            senderID: "coach",
            addressing: .direct(participantID),
            representation: representation,
            payload: Data(),
            intent: "robot.kick"
        )
        let pendingPlan = await runtime.planRoute(for: message)
        let approvedPlan = await runtime.authorize(pendingPlan, using: ApprovingPolicyAuthorizer())

        #expect(pendingPlan.policyDecision.state == .requiresApproval)
        #expect(approvedPlan.policyDecision.state == .approved)
        #expect(approvedPlan.isPreExecutionAuthorized)
    }

    @Test
    func bestEffortLatestDeliveryCarriesFreshnessOrdering() {
        let delivery = DeliveryOption(
            semantics: .bestEffortLatest,
            maximumLatency: 0.05,
            expiry: 0.1,
            freshnessOrdering: FreshnessOrdering(kind: .sequence, field: "sequence")
        )

        #expect(delivery.semantics == .bestEffortLatest)
        #expect(delivery.freshnessOrdering.kind == .sequence)
        #expect(delivery.freshnessOrdering.field == "sequence")
    }
}

private struct ApprovingPolicyAuthorizer: PolicyAuthorizer {
    func authorize(_ request: PolicyRequest) async -> PolicyDecision {
        PolicyDecision(
            state: .approved,
            policyIDs: request.policyIDs,
            reasons: ["approved by test authorizer"]
        )
    }
}
