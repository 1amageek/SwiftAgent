import Distributed
import Foundation
import Testing
@testable import SwiftAgent
@testable import SwiftAgentSymbio

@Suite("Symbio E2E", .serialized)
struct SymbioE2ETests {
    @Test
    func runtimesDiscoverAndInvokeRemoteCapabilityEndToEnd() async throws {
        let clientSystem = SymbioActorSystem()
        let serverSystem = SymbioActorSystem()
        let clientTransport = InMemorySymbioTransport(localID: "client")
        let serverTransport = InMemorySymbioTransport(localID: "server")
        let clientRuntime = SymbioRuntime(actorSystem: clientSystem, transport: clientTransport)
        let serverRuntime = SymbioRuntime(actorSystem: serverSystem, transport: serverTransport)

        try await clientRuntime.start()
        try await serverRuntime.start()
        let serverParticipant = try await serverRuntime.spawn {
            ComputeAgent(runtime: serverRuntime, actorSystem: serverSystem)
        }

        await clientTransport.connect(to: serverTransport, descriptor: serverParticipant.descriptor)
        let discovered = try await waitForParticipant(serverParticipant.id, in: clientRuntime)
        let payload = Data("remote input".utf8)

        let result = try await clientRuntime.invoke(
            "agent.action.compute",
            on: discovered.id,
            with: payload,
            senderID: "client"
        )

        #expect(result == payload)
        #expect(await clientTransport.invocationCount() == 1)
        #expect(await clientRuntime.participantView(for: discovered.id)?.evidence.map(\.kind) == [.successfulInvocation])

        try await clientRuntime.stop()
        try await serverRuntime.stop()
    }

    @Test
    func policyGateBlocksRemoteInvocationBeforeTransport() async throws {
        let clientSystem = SymbioActorSystem()
        let serverSystem = SymbioActorSystem()
        let clientTransport = InMemorySymbioTransport(localID: "client")
        let serverTransport = InMemorySymbioTransport(localID: "server")
        let clientRuntime = SymbioRuntime(actorSystem: clientSystem, transport: clientTransport)
        let serverRuntime = SymbioRuntime(actorSystem: serverSystem, transport: serverTransport)

        try await clientRuntime.start()
        try await serverRuntime.start()
        let serverParticipant = try await serverRuntime.spawn {
            ComputeAgent(runtime: serverRuntime, actorSystem: serverSystem)
        }
        let representation = MessageRepresentation.typedPayload(schema: "agent.action.compute")
        let protectedDescriptor = ParticipantDescriptor(
            id: serverParticipant.id,
            displayName: serverParticipant.descriptor.displayName,
            kind: .agent,
            representations: [representation],
            capabilityContracts: [
                CapabilityContract(
                    id: "agent.action.compute",
                    input: representation,
                    sideEffectLevel: .physical,
                    requiredPolicies: ["remote.compute.approval"]
                )
            ]
        )

        await clientTransport.connect(to: serverTransport, descriptor: protectedDescriptor)
        _ = try await waitForParticipant(serverParticipant.id, in: clientRuntime)

        await #expect(throws: SymbioRuntimeError.self) {
            _ = try await clientRuntime.invoke(
                "agent.action.compute",
                on: serverParticipant.id,
                with: Data("blocked".utf8),
                senderID: "client"
            )
        }
        #expect(await clientTransport.invocationCount() == 0)

        let approved = try await clientRuntime.invoke(
            "agent.action.compute",
            on: serverParticipant.id,
            with: Data("approved".utf8),
            senderID: "client",
            authorizer: E2EApprovingPolicyAuthorizer()
        )

        #expect(approved == Data("approved".utf8))
        #expect(await clientTransport.invocationCount() == 1)

        try await clientRuntime.stop()
        try await serverRuntime.stop()
    }

    @Test
    func matterLockRequiresApprovalBeforeRemoteStateChange() async throws {
        let clientSystem = SymbioActorSystem()
        let serverSystem = SymbioActorSystem()
        let clientTransport = InMemorySymbioTransport(localID: "home.controller")
        let serverTransport = InMemorySymbioTransport(localID: "matter.lock.front")
        let clientRuntime = SymbioRuntime(actorSystem: clientSystem, transport: clientTransport)
        let serverRuntime = SymbioRuntime(actorSystem: serverSystem, transport: serverTransport)

        try await clientRuntime.start()
        try await serverRuntime.start()
        let lock = try await serverRuntime.spawn {
            MatterLockAgent(runtime: serverRuntime, actorSystem: serverSystem)
        }
        let representation = MessageRepresentation.typedPayload(schema: "matter.lock.setState")
        let descriptor = ParticipantDescriptor(
            id: lock.id,
            displayName: "Front Door Lock",
            kind: .device,
            representations: [representation],
            capabilityContracts: [
                CapabilityContract(
                    id: "matter.lock.setState",
                    input: representation,
                    sideEffectLevel: .physical,
                    requiredPolicies: ["home.lock.approval"]
                )
            ]
        )

        await clientTransport.connect(to: serverTransport, descriptor: descriptor)
        _ = try await waitForParticipant(lock.id, in: clientRuntime)

        await #expect(throws: SymbioRuntimeError.self) {
            _ = try await clientRuntime.invoke(
                "matter.lock.setState",
                on: lock.id,
                with: Data("locked".utf8),
                senderID: "home.controller"
            )
        }
        #expect(await clientTransport.invocationCount() == 0)

        let response = try await clientRuntime.invoke(
            "matter.lock.setState",
            on: lock.id,
            with: Data("locked".utf8),
            senderID: "home.controller",
            authorizer: E2EApprovingPolicyAuthorizer()
        )

        #expect(response == Data("locked".utf8))
        #expect(await clientTransport.invocationCount() == 1)
        #expect(await clientRuntime.participantView(for: lock.id)?.evidence.map(\.kind) == [.successfulInvocation])

        try await clientRuntime.stop()
        try await serverRuntime.stop()
    }

    @Test
    func droneSwarmUsesFreshTelemetryAndDegradesWithMemberLoss() async throws {
        let clientSystem = SymbioActorSystem()
        let drone1System = SymbioActorSystem()
        let drone2System = SymbioActorSystem()
        let drone3System = SymbioActorSystem()
        let clientTransport = InMemorySymbioTransport(localID: "swarm.operator")
        let drone1Transport = InMemorySymbioTransport(localID: "drone.1")
        let drone2Transport = InMemorySymbioTransport(localID: "drone.2")
        let drone3Transport = InMemorySymbioTransport(localID: "drone.3")
        let clientRuntime = SymbioRuntime(actorSystem: clientSystem, transport: clientTransport)
        let drone1Runtime = SymbioRuntime(actorSystem: drone1System, transport: drone1Transport)
        let drone2Runtime = SymbioRuntime(actorSystem: drone2System, transport: drone2Transport)
        let drone3Runtime = SymbioRuntime(actorSystem: drone3System, transport: drone3Transport)

        try await clientRuntime.start()
        try await drone1Runtime.start()
        try await drone2Runtime.start()
        try await drone3Runtime.start()
        let drone1 = try await drone1Runtime.spawn {
            DroneTelemetryAgent(runtime: drone1Runtime, actorSystem: drone1System)
        }
        let drone2 = try await drone2Runtime.spawn {
            DroneTelemetryAgent(runtime: drone2Runtime, actorSystem: drone2System)
        }
        let drone3 = try await drone3Runtime.spawn {
            DroneTelemetryAgent(runtime: drone3Runtime, actorSystem: drone3System)
        }

        await clientTransport.connect(to: drone1Transport, descriptor: droneDescriptor(for: drone1, displayName: "Drone 1"))
        await clientTransport.connect(to: drone2Transport, descriptor: droneDescriptor(for: drone2, displayName: "Drone 2"))
        await clientTransport.connect(to: drone3Transport, descriptor: droneDescriptor(for: drone3, displayName: "Drone 3"))
        _ = try await waitForParticipant(drone1.id, in: clientRuntime)
        _ = try await waitForParticipant(drone2.id, in: clientRuntime)
        _ = try await waitForParticipant(drone3.id, in: clientRuntime)

        await clientRuntime.observe(droneTelemetryAffordance(for: drone1.id))
        await clientRuntime.observe(droneTelemetryAffordance(for: drone2.id))
        await clientRuntime.observe(droneTelemetryAffordance(for: drone3.id))
        await clientRuntime.register(AggregateParticipantDescriptor(
            id: "swarm.alpha",
            displayName: "Swarm Alpha",
            kind: .swarm,
            members: [
                AggregateMember(id: drone1.id),
                AggregateMember(id: drone2.id),
                AggregateMember(id: drone3.id)
            ],
            rollupPolicy: RollupPolicy(
                availabilityRule: .quorum(0.66),
                evidenceRule: .minimumCount(2),
                degradationMode: .partialCapability
            )
        ))

        let telemetry = try await clientRuntime.invoke(
            "drone.telemetry.latest",
            on: drone1.id,
            with: Data("frame:42".utf8),
            senderID: "swarm.operator"
        )

        #expect(telemetry == Data("frame:42".utf8))
        #expect(await clientRuntime.participantView(for: "swarm.alpha")?.availability.state == .available)

        await clientRuntime.updateAvailability(.unavailable(reason: "battery"), for: drone2.id)
        #expect(await clientRuntime.participantView(for: "swarm.alpha")?.availability.state == .available)

        await clientRuntime.block(drone1.id, reason: "operator inhibited")
        #expect(await clientRuntime.participantView(for: "swarm.alpha")?.availability.state == .degraded)

        await clientRuntime.updateAvailability(.unavailable(reason: "lost"), for: drone3.id)
        #expect(await clientRuntime.participantView(for: "swarm.alpha")?.availability.state == .unavailable)

        try await clientRuntime.stop()
        try await drone1Runtime.stop()
        try await drone2Runtime.stop()
        try await drone3Runtime.stop()
    }

    @Test
    func soccerTeamPlansGroupPlayAndRequiresMotionApproval() async throws {
        let clientSystem = SymbioActorSystem()
        let strikerSystem = SymbioActorSystem()
        let supportSystem = SymbioActorSystem()
        let clientTransport = InMemorySymbioTransport(localID: "coach")
        let strikerTransport = InMemorySymbioTransport(localID: "striker")
        let supportTransport = InMemorySymbioTransport(localID: "support")
        let clientRuntime = SymbioRuntime(actorSystem: clientSystem, transport: clientTransport)
        let strikerRuntime = SymbioRuntime(actorSystem: strikerSystem, transport: strikerTransport)
        let supportRuntime = SymbioRuntime(actorSystem: supportSystem, transport: supportTransport)

        try await clientRuntime.start()
        try await strikerRuntime.start()
        try await supportRuntime.start()
        let striker = try await strikerRuntime.spawn {
            SoccerRobotAgent(runtime: strikerRuntime, actorSystem: strikerSystem)
        }
        let support = try await supportRuntime.spawn {
            SoccerRobotAgent(runtime: supportRuntime, actorSystem: supportSystem)
        }
        let strikerDescriptor = soccerDescriptor(for: striker, role: "striker")
        let supportDescriptor = soccerDescriptor(for: support, role: "support")

        await clientTransport.connect(to: strikerTransport, descriptor: strikerDescriptor)
        await clientTransport.connect(to: supportTransport, descriptor: supportDescriptor)
        _ = try await waitForParticipant(striker.id, in: clientRuntime)
        _ = try await waitForParticipant(support.id, in: clientRuntime)

        let representation = MessageRepresentation.typedPayload(schema: "soccer.pass.execute")
        let play = Message(
            senderID: "coach",
            addressing: .group([striker.id, support.id]),
            representation: representation,
            payload: Data("triangle-pass".utf8),
            intent: "soccer.pass.execute"
        )
        let plan = await clientRuntime.planRoute(for: play)

        #expect(plan.steps.map(\.kind) == [.send, .send])
        #expect(plan.requiredPolicies == ["field.motion.approval"])
        #expect(plan.policyDecision.state == .requiresApproval)

        await #expect(throws: SymbioRuntimeError.self) {
            _ = try await clientRuntime.invoke(
                "soccer.pass.execute",
                on: striker.id,
                with: Data("triangle-pass".utf8),
                senderID: "coach"
            )
        }
        #expect(await clientTransport.invocationCount() == 0)

        let executed = try await clientRuntime.invoke(
            "soccer.pass.execute",
            on: striker.id,
            with: Data("triangle-pass".utf8),
            senderID: "coach",
            authorizer: E2EApprovingPolicyAuthorizer()
        )

        #expect(executed == Data("triangle-pass".utf8))
        #expect(await clientTransport.invocationCount() == 1)

        try await clientRuntime.stop()
        try await strikerRuntime.stop()
        try await supportRuntime.stop()
    }
}

distributed actor MatterLockAgent: Communicable, CapabilityProviding {
    typealias ActorSystem = SymbioActorSystem

    let runtime: SymbioRuntime

    nonisolated var perceptions: [any Perception] {
        []
    }

    nonisolated var providedCapabilities: Set<String> {
        ["matter.lock.setState"]
    }

    init(runtime: SymbioRuntime, actorSystem: SymbioActorSystem) {
        self.runtime = runtime
        self.actorSystem = actorSystem
    }

    distributed func receive(_ data: Data, perception: String) async throws -> Data? {
        nil
    }

    distributed func invokeCapability(_ data: Data, capability: String) async throws -> Data {
        data
    }
}

distributed actor DroneTelemetryAgent: Communicable, CapabilityProviding {
    typealias ActorSystem = SymbioActorSystem

    let runtime: SymbioRuntime

    nonisolated var perceptions: [any Perception] {
        []
    }

    nonisolated var providedCapabilities: Set<String> {
        ["drone.telemetry.latest"]
    }

    init(runtime: SymbioRuntime, actorSystem: SymbioActorSystem) {
        self.runtime = runtime
        self.actorSystem = actorSystem
    }

    distributed func receive(_ data: Data, perception: String) async throws -> Data? {
        nil
    }

    distributed func invokeCapability(_ data: Data, capability: String) async throws -> Data {
        data
    }
}

distributed actor SoccerRobotAgent: Communicable, CapabilityProviding {
    typealias ActorSystem = SymbioActorSystem

    let runtime: SymbioRuntime

    nonisolated var perceptions: [any Perception] {
        []
    }

    nonisolated var providedCapabilities: Set<String> {
        ["soccer.pass.execute"]
    }

    init(runtime: SymbioRuntime, actorSystem: SymbioActorSystem) {
        self.runtime = runtime
        self.actorSystem = actorSystem
    }

    distributed func receive(_ data: Data, perception: String) async throws -> Data? {
        nil
    }

    distributed func invokeCapability(_ data: Data, capability: String) async throws -> Data {
        data
    }
}

private actor InMemorySymbioTransport: SymbioTransport {
    nonisolated let events: AsyncStream<SymbioTransportEvent>
    private let localID: ParticipantID
    private let continuation: AsyncStream<SymbioTransportEvent>.Continuation
    private var peers: [ParticipantID: InMemorySymbioTransport] = [:]
    private var invocationHandler: SymbioIncomingInvocationHandler?
    private var invocations: [SymbioInvocationEnvelope] = []

    init(localID: ParticipantID) {
        self.localID = localID
        let stream = AsyncStream<SymbioTransportEvent>.makeStream()
        self.events = stream.stream
        self.continuation = stream.continuation
    }

    func start() async throws {}

    func shutdown() async throws {
        peers.removeAll()
        invocationHandler = nil
        continuation.finish()
    }

    func setInvocationHandler(_ handler: @escaping SymbioIncomingInvocationHandler) async {
        invocationHandler = handler
    }

    func removeInvocationHandler() async {
        invocationHandler = nil
    }

    func connect(to peer: InMemorySymbioTransport, descriptor: ParticipantDescriptor) {
        peers[descriptor.id] = peer
        continuation.yield(.peerDiscovered(descriptor))
    }

    func invoke(
        _ envelope: SymbioInvocationEnvelope,
        on peerID: ParticipantID,
        timeout: Duration
    ) async throws -> SymbioInvocationReply {
        guard let peer = peers[peerID] else {
            throw SymbioError.noTransportAvailable
        }
        invocations.append(envelope)
        return await peer.handle(envelope, senderID: localID)
    }

    func invocationCount() -> Int {
        invocations.count
    }

    private func handle(
        _ envelope: SymbioInvocationEnvelope,
        senderID: ParticipantID
    ) async -> SymbioInvocationReply {
        guard let invocationHandler else {
            return .failure(
                invocationID: envelope.invocationID,
                code: SymbioErrorCode.notFound.rawValue,
                message: "No invocation handler is registered"
            )
        }
        return await invocationHandler(envelope, senderID)
    }
}

private struct E2EApprovingPolicyAuthorizer: PolicyAuthorizer {
    func authorize(_ request: PolicyRequest) async -> PolicyDecision {
        PolicyDecision(
            state: .approved,
            policyIDs: request.policyIDs,
            reasons: ["approved by e2e test"]
        )
    }
}

private enum SymbioE2EError: Error {
    case participantNotDiscovered(ParticipantID)
}

private func droneDescriptor(for participant: ParticipantView, displayName: String) -> ParticipantDescriptor {
    let representation = MessageRepresentation.typedPayload(schema: "drone.telemetry.latest")
    return ParticipantDescriptor(
        id: participant.id,
        displayName: displayName,
        kind: .robot,
        representations: [representation],
        capabilityContracts: [
            CapabilityContract(
                id: "drone.telemetry.latest",
                input: representation,
                sideEffectLevel: .none
            )
        ]
    )
}

private func droneTelemetryAffordance(for participantID: ParticipantID) -> Affordance {
    let representation = MessageRepresentation.typedPayload(schema: "drone.telemetry.latest")
    let contract = CapabilityContract(
        id: "drone.telemetry.latest",
        input: representation,
        sideEffectLevel: .none
    )
    return Affordance(
        id: contract.id,
        ownerID: participantID,
        contract: contract,
        deliveryOptions: [
            DeliveryOption(
                semantics: .bestEffortLatest,
                maximumLatency: 0.05,
                expiry: 0.1,
                freshnessOrdering: FreshnessOrdering(kind: .sequence, field: "frame")
            )
        ],
        evidenceIDs: ["telemetry.\(participantID.rawValue).freshness"]
    )
}

private func soccerDescriptor(for participant: ParticipantView, role: String) -> ParticipantDescriptor {
    let representation = MessageRepresentation.typedPayload(schema: "soccer.pass.execute")
    return ParticipantDescriptor(
        id: participant.id,
        displayName: role,
        kind: .robot,
        representations: [representation],
        capabilityContracts: [
            CapabilityContract(
                id: "soccer.pass.execute",
                input: representation,
                sideEffectLevel: .physical,
                requiredPolicies: ["field.motion.approval"]
            )
        ],
        metadata: ["soccer.role": role]
    )
}

private func waitForParticipant(
    _ id: ParticipantID,
    in runtime: SymbioRuntime
) async throws -> ParticipantView {
    for _ in 0..<50 {
        if let view = await runtime.participantView(for: id) {
            return view
        }
        try await Task.sleep(for: .milliseconds(10))
    }
    throw SymbioE2EError.participantNotDiscovered(id)
}
