import Testing
import Foundation
import Distributed
@testable import SwiftAgent
@testable import SwiftAgentSymbio

struct WorkPerception: Perception {
    let identifier = "work"
    typealias Signal = WorkSignal
}

struct WorkSignal: Sendable, Codable, Equatable {
    let task: String
}

actor SignalTracker {
    static let shared = SignalTracker()
    private var counts: [String: Int] = [:]

    func record(_ id: String) {
        counts[id, default: 0] += 1
    }

    func count(_ id: String) -> Int {
        counts[id] ?? 0
    }

    func reset() {
        counts.removeAll()
    }
}

actor TestSymbioTransport: SymbioTransport {
    nonisolated let events: AsyncStream<SymbioTransportEvent>
    private let continuation: AsyncStream<SymbioTransportEvent>.Continuation
    private var invocations: [(ParticipantID, SymbioInvocationEnvelope)] = []

    init() {
        let stream = AsyncStream<SymbioTransportEvent>.makeStream()
        self.events = stream.stream
        self.continuation = stream.continuation
    }

    func start() async throws {}

    func shutdown() async throws {
        continuation.finish()
    }

    func setInvocationHandler(_ handler: @escaping SymbioIncomingInvocationHandler) async {}

    func removeInvocationHandler() async {}

    func invoke(
        _ envelope: SymbioInvocationEnvelope,
        on peerID: ParticipantID,
        timeout: Duration
    ) async throws -> SymbioInvocationReply {
        invocations.append((peerID, envelope))
        return .success(invocationID: envelope.invocationID, result: envelope.arguments)
    }

    func emit(_ event: SymbioTransportEvent) {
        continuation.yield(event)
    }

    func invocationCount() -> Int {
        invocations.count
    }
}

distributed actor TestWorkerAgent: Communicable, Terminatable {
    typealias ActorSystem = SymbioActorSystem

    let runtime: SymbioRuntime

    nonisolated var perceptions: [any Perception] {
        [WorkPerception()]
    }

    nonisolated var agentID: String {
        id.hexString
    }

    init(runtime: SymbioRuntime, actorSystem: SymbioActorSystem) {
        self.runtime = runtime
        self.actorSystem = actorSystem
    }

    distributed func receive(_ data: Data, perception: String) async throws -> Data? {
        await SignalTracker.shared.record(id.hexString)
        return nil
    }

    nonisolated func terminate() async {}
}

distributed actor ComputeAgent: Communicable, CapabilityProviding {
    typealias ActorSystem = SymbioActorSystem

    let runtime: SymbioRuntime

    nonisolated var perceptions: [any Perception] {
        [WorkPerception()]
    }

    nonisolated var providedCapabilities: Set<String> {
        ["agent.action.compute"]
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

private enum TestCapabilityError: Error {
    case failed
}

distributed actor FailingComputeAgent: Communicable, CapabilityProviding {
    typealias ActorSystem = SymbioActorSystem

    let runtime: SymbioRuntime

    nonisolated var perceptions: [any Perception] {
        [WorkPerception()]
    }

    nonisolated var providedCapabilities: Set<String> {
        ["agent.action.compute"]
    }

    init(runtime: SymbioRuntime, actorSystem: SymbioActorSystem) {
        self.runtime = runtime
        self.actorSystem = actorSystem
    }

    distributed func receive(_ data: Data, perception: String) async throws -> Data? {
        nil
    }

    distributed func invokeCapability(_ data: Data, capability: String) async throws -> Data {
        throw TestCapabilityError.failed
    }
}

private struct ApprovingPolicyAuthorizer: PolicyAuthorizer {
    func authorize(_ request: PolicyRequest) async -> PolicyDecision {
        PolicyDecision(
            state: .approved,
            policyIDs: request.policyIDs,
            reasons: ["approved by runtime test"]
        )
    }
}

@Suite("SymbioRuntime participant tests", .serialized)
struct SymbioRuntimeTests {
    @Test
    func spawnRegistersParticipantAffordances() async throws {
        let actorSystem = SymbioActorSystem()
        let runtime = SymbioRuntime(actorSystem: actorSystem)

        let participant = try await runtime.spawn {
            TestWorkerAgent(runtime: runtime, actorSystem: actorSystem)
        }

        #expect(participant.descriptor.kind == .agent)
        #expect(participant.affordances.map(\.contract.id) == ["agent.perception.work"])
        #expect(await runtime.participantView(for: participant.id)?.availability.state == .available)
    }

    @Test
    func sendToLocalParticipantDeliversSignal() async throws {
        await SignalTracker.shared.reset()
        let actorSystem = SymbioActorSystem()
        let runtime = SymbioRuntime(actorSystem: actorSystem)
        let participant = try await runtime.spawn {
            TestWorkerAgent(runtime: runtime, actorSystem: actorSystem)
        }

        _ = try await runtime.send(WorkSignal(task: "build"), to: participant.id, perception: "work")

        #expect(await SignalTracker.shared.count(participant.id.rawValue) == 1)
    }

    @Test
    func invokeLocalCapabilityUsesProvider() async throws {
        let actorSystem = SymbioActorSystem()
        let runtime = SymbioRuntime(actorSystem: actorSystem)
        let participant = try await runtime.spawn {
            ComputeAgent(runtime: runtime, actorSystem: actorSystem)
        }
        let payload = Data("input".utf8)

        let result = try await runtime.invoke("agent.action.compute", on: participant.id, with: payload)

        #expect(result == payload)
    }

    @Test
    func failedLocalCapabilityRecordsEvidence() async throws {
        let actorSystem = SymbioActorSystem()
        let runtime = SymbioRuntime(actorSystem: actorSystem)
        let participant = try await runtime.spawn {
            FailingComputeAgent(runtime: runtime, actorSystem: actorSystem)
        }

        await #expect(throws: TestCapabilityError.self) {
            _ = try await runtime.invoke("agent.action.compute", on: participant.id, with: Data("input".utf8))
        }

        let view = try #require(await runtime.participantView(for: participant.id))
        #expect(view.evidence.map(\.kind) == [.failedInvocation])
    }

    @Test
    func transportDescriptorRegistersParticipant() async throws {
        let actorSystem = SymbioActorSystem()
        let transport = TestSymbioTransport()
        let runtime = SymbioRuntime(actorSystem: actorSystem, transport: transport)
        let representation = MessageRepresentation.typedPayload(schema: "agent.action.compute")
        let descriptor = ParticipantDescriptor(
            id: "remote.agent",
            displayName: "Remote Agent",
            kind: .agent,
            representations: [representation],
            capabilityContracts: [
                CapabilityContract(id: "agent.action.compute", input: representation)
            ]
        )

        try await runtime.start()
        await transport.emit(.peerDiscovered(descriptor))
        try await Task.sleep(for: .milliseconds(20))

        let view = try #require(await runtime.participantView(for: "remote.agent"))
        #expect(view.descriptor.displayName == "Remote Agent")
        #expect(view.affordances.map(\.contract.id) == ["agent.action.compute"])
        try await runtime.stop()
    }

    @Test
    func staleUnavailableParticipantCannotBeInvoked() async throws {
        let actorSystem = SymbioActorSystem()
        let transport = TestSymbioTransport()
        let runtime = SymbioRuntime(actorSystem: actorSystem, transport: transport)
        let representation = MessageRepresentation.typedPayload(schema: "agent.action.compute")
        let descriptor = ParticipantDescriptor(
            id: "remote.agent",
            kind: .agent,
            representations: [representation],
            capabilityContracts: [
                CapabilityContract(id: "agent.action.compute", input: representation)
            ]
        )

        await runtime.register(descriptor)
        await runtime.updateAvailability(.unavailable(reason: "lost"), for: "remote.agent")

        await #expect(throws: SymbioRuntimeError.self) {
            _ = try await runtime.invoke("agent.action.compute", on: "remote.agent", with: Data())
        }
        #expect(await transport.invocationCount() == 0)
    }

    @Test
    func invokeRequiresMatchingAffordance() async throws {
        let actorSystem = SymbioActorSystem()
        let transport = TestSymbioTransport()
        let runtime = SymbioRuntime(actorSystem: actorSystem, transport: transport)
        await runtime.register(ParticipantDescriptor(
            id: "remote.agent",
            kind: .agent,
            representations: [.typedPayload(schema: "agent.action.other")]
        ))

        await #expect(throws: SymbioRuntimeError.self) {
            _ = try await runtime.invoke("agent.action.compute", on: "remote.agent", with: Data())
        }
        #expect(await transport.invocationCount() == 0)
    }

    @Test
    func policyProtectedInvokeRequiresAuthorizer() async throws {
        let actorSystem = SymbioActorSystem()
        let transport = TestSymbioTransport()
        let runtime = SymbioRuntime(actorSystem: actorSystem, transport: transport)
        let representation = MessageRepresentation.typedPayload(schema: "robot.motion.execute")
        await runtime.register(ParticipantDescriptor(
            id: "robot.arm.1",
            kind: .robot,
            representations: [representation],
            capabilityContracts: [
                CapabilityContract(
                    id: "robot.motion.execute",
                    input: representation,
                    sideEffectLevel: .physical,
                    requiredPolicies: ["physical.motion.approval"]
                )
            ]
        ))

        await #expect(throws: SymbioRuntimeError.self) {
            _ = try await runtime.invoke("robot.motion.execute", on: "robot.arm.1", with: Data("move".utf8))
        }
        #expect(await transport.invocationCount() == 0)

        let result = try await runtime.invoke(
            "robot.motion.execute",
            on: "robot.arm.1",
            with: Data("move".utf8),
            authorizer: ApprovingPolicyAuthorizer()
        )
        #expect(result == Data("move".utf8))
        #expect(await transport.invocationCount() == 1)
    }

    @Test
    func stopFinishesChangesStream() async throws {
        let actorSystem = SymbioActorSystem()
        let runtime = SymbioRuntime(actorSystem: actorSystem)
        let changes = await runtime.changes
        try await runtime.stop()
        var iterator = changes.makeAsyncIterator()
        #expect(await iterator.next() == nil)
    }
}
