import Testing
import Foundation
import Distributed
@testable import SwiftAgent
@testable import SwiftAgentSymbio

// MARK: - Test Perceptions

/// Test perception for work signals
struct WorkPerception: Perception {
    let identifier = "work"
    typealias Signal = WorkSignal
}

/// Test perception for result signals
struct ResultPerception: Perception {
    let identifier = "result"
    typealias Signal = ResultSignal
}

// MARK: - Test Signals

/// Work signal for testing
struct WorkSignal: Sendable, Codable {
    let task: String
    let priority: Int

    init(task: String, priority: Int = 0) {
        self.task = task
        self.priority = priority
    }
}

/// Result signal for testing
struct ResultSignal: Sendable, Codable {
    let output: String
    let success: Bool
}

// MARK: - Shared State for Tests

/// Actor to track termination calls
actor TerminationTracker {
    static let shared = TerminationTracker()

    private var terminatedIDs: Set<String> = []

    func markTerminated(_ id: String) {
        terminatedIDs.insert(id)
    }

    func isTerminated(_ id: String) -> Bool {
        terminatedIDs.contains(id)
    }

    func reset() {
        terminatedIDs.removeAll()
    }
}

/// Actor to track received signals
actor SignalTracker {
    static let shared = SignalTracker()

    private var signalCounts: [String: Int] = [:]

    func recordSignal(for agentID: String) {
        signalCounts[agentID, default: 0] += 1
    }

    func signalCount(for agentID: String) -> Int {
        signalCounts[agentID] ?? 0
    }

    func reset() {
        signalCounts.removeAll()
    }
}

// MARK: - Test Agents

/// Simple test agent that implements Communicable
distributed actor TestWorkerAgent: Communicable, Terminatable {
    typealias ActorSystem = SymbioActorSystem

    let community: Community

    nonisolated var perceptions: [any Perception] {
        [WorkPerception()]
    }

    /// Get the agent ID string (nonisolated access via distributed actor identity)
    nonisolated var agentID: String {
        self.id.hexString
    }

    init(community: Community, actorSystem: SymbioActorSystem) {
        self.community = community
        self.actorSystem = actorSystem
    }

    distributed func receive(_ data: Data, perception: String) async throws -> Data? {
        await SignalTracker.shared.recordSignal(for: self.id.hexString)
        return nil
    }

    nonisolated func terminate() async {
        await TerminationTracker.shared.markTerminated(self.id.hexString)
    }
}

/// Agent with multiple perceptions
distributed actor MultiPerceptionAgent: Communicable {
    typealias ActorSystem = SymbioActorSystem

    let community: Community

    nonisolated var perceptions: [any Perception] {
        [WorkPerception(), ResultPerception()]
    }

    init(community: Community, actorSystem: SymbioActorSystem) {
        self.community = community
        self.actorSystem = actorSystem
    }

    distributed func receive(_ data: Data, perception: String) async throws -> Data? {
        // Handle signal
        return nil
    }
}

/// Agent without Terminatable (for testing graceful degradation)
distributed actor NonTerminatableAgent: Communicable {
    typealias ActorSystem = SymbioActorSystem

    let community: Community

    nonisolated var perceptions: [any Perception] {
        [WorkPerception()]
    }

    init(community: Community, actorSystem: SymbioActorSystem) {
        self.community = community
        self.actorSystem = actorSystem
    }

    distributed func receive(_ data: Data, perception: String) async throws -> Data? {
        return nil
    }
}

// MARK: - Community Spawn Tests

@Suite("Community Spawn Tests", .serialized)
struct CommunitySpawnTests {

    @Test("spawn creates a local agent and returns Member")
    func spawnCreatesLocalAgent() async throws {
        let actorSystem = SymbioActorSystem()
        let community = Community(actorSystem: actorSystem)

        let member = try await community.spawn {
            TestWorkerAgent(community: community, actorSystem: actorSystem)
        }

        // Verify member properties
        #expect(!member.id.isEmpty)
        #expect(member.isAvailable == true)
        #expect(member.metadata["location"] == "local")
        #expect(member.accepts.contains("work"))
    }

    @Test("spawn adds agent to members list")
    func spawnAddsToMembers() async throws {
        let actorSystem = SymbioActorSystem()
        let community = Community(actorSystem: actorSystem)

        let member = try await community.spawn {
            TestWorkerAgent(community: community, actorSystem: actorSystem)
        }

        let members = await community.members
        #expect(members.count == 1)
        #expect(members.first?.id == member.id)
    }

    @Test("spawn multiple agents creates multiple members")
    func spawnMultipleAgents() async throws {
        let actorSystem = SymbioActorSystem()
        let community = Community(actorSystem: actorSystem)

        _ = try await community.spawn {
            TestWorkerAgent(community: community, actorSystem: actorSystem)
        }
        _ = try await community.spawn {
            TestWorkerAgent(community: community, actorSystem: actorSystem)
        }
        _ = try await community.spawn {
            TestWorkerAgent(community: community, actorSystem: actorSystem)
        }

        let members = await community.members
        #expect(members.count == 3)

        // All should have unique IDs
        let ids = Set(members.map { $0.id })
        #expect(ids.count == 3)

        // All should be available
        #expect(members.allSatisfy { $0.isAvailable })
    }

    @Test("spawn agent with multiple perceptions")
    func spawnAgentWithMultiplePerceptions() async throws {
        let actorSystem = SymbioActorSystem()
        let community = Community(actorSystem: actorSystem)

        let member = try await community.spawn {
            MultiPerceptionAgent(community: community, actorSystem: actorSystem)
        }

        #expect(member.accepts.contains("work"))
        #expect(member.accepts.contains("result"))
        #expect(member.accepts.count == 2)
    }

    @Test("whoCanReceive finds spawned agents")
    func whoCanReceiveFindsSpawnedAgents() async throws {
        let actorSystem = SymbioActorSystem()
        let community = Community(actorSystem: actorSystem)

        _ = try await community.spawn {
            TestWorkerAgent(community: community, actorSystem: actorSystem)
        }
        _ = try await community.spawn {
            TestWorkerAgent(community: community, actorSystem: actorSystem)
        }

        let workReceivers = await community.whoCanReceive("work")
        #expect(workReceivers.count == 2)

        let resultReceivers = await community.whoCanReceive("result")
        #expect(resultReceivers.count == 0)
    }
}

// MARK: - Community Terminate Tests

@Suite("Community Terminate Tests", .serialized)
struct CommunityTerminateTests {

    init() async {
        await TerminationTracker.shared.reset()
    }

    @Test("terminate removes agent from members")
    func terminateRemovesFromMembers() async throws {
        let actorSystem = SymbioActorSystem()
        let community = Community(actorSystem: actorSystem)

        let member = try await community.spawn {
            TestWorkerAgent(community: community, actorSystem: actorSystem)
        }

        #expect(await community.members.count == 1)

        try await community.terminate(member)

        #expect(await community.members.count == 0)
    }

    @Test("terminate calls Terminatable.terminate()")
    func terminateCallsTerminatable() async throws {
        await TerminationTracker.shared.reset()

        let actorSystem = SymbioActorSystem()
        let community = Community(actorSystem: actorSystem)

        let member = try await community.spawn {
            TestWorkerAgent(community: community, actorSystem: actorSystem)
        }

        // Verify not terminated yet
        let beforeTerminate = await TerminationTracker.shared.isTerminated(member.id)
        #expect(beforeTerminate == false)

        // Terminate
        try await community.terminate(member)

        // Verify terminate was called
        let afterTerminate = await TerminationTracker.shared.isTerminated(member.id)
        #expect(afterTerminate == true)
    }

    @Test("terminate non-Terminatable agent succeeds")
    func terminateNonTerminatableSucceeds() async throws {
        let actorSystem = SymbioActorSystem()
        let community = Community(actorSystem: actorSystem)

        let member = try await community.spawn {
            NonTerminatableAgent(community: community, actorSystem: actorSystem)
        }

        // Should not throw
        try await community.terminate(member)

        #expect(await community.members.count == 0)
    }

    @Test("terminate unknown member throws error")
    func terminateUnknownMemberThrows() async throws {
        let actorSystem = SymbioActorSystem()
        let community = Community(actorSystem: actorSystem)

        let fakeMember = Member(
            id: "fake-id",
            name: nil,
            accepts: [],
            provides: [],
            isAvailable: true,
            metadata: ["location": "local"]
        )

        await #expect(throws: CommunityError.self) {
            try await community.terminate(fakeMember)
        }
    }

    @Test("terminate remote member throws error")
    func terminateRemoteMemberThrows() async throws {
        let actorSystem = SymbioActorSystem()
        let community = Community(actorSystem: actorSystem)

        let remoteMember = Member(
            id: "remote-agent",
            name: nil,
            accepts: ["work"],
            provides: [],
            isAvailable: true,
            metadata: ["location": "remote"]
        )

        await #expect(throws: CommunityError.self) {
            try await community.terminate(remoteMember)
        }
    }
}

// MARK: - Community Send Tests

@Suite("Community Send Tests", .serialized)
struct CommunitySendTests {

    init() async {
        await SignalTracker.shared.reset()
    }

    @Test("send to local agent delivers signal")
    func sendToLocalAgentDeliversSignal() async throws {
        await SignalTracker.shared.reset()

        let actorSystem = SymbioActorSystem()
        let community = Community(actorSystem: actorSystem)

        let member = try await community.spawn {
            TestWorkerAgent(community: community, actorSystem: actorSystem)
        }

        let signal = WorkSignal(task: "test-task", priority: 5)
        _ = try await community.send(signal, to: member, perception: "work")

        let count = await SignalTracker.shared.signalCount(for: member.id)
        #expect(count == 1)
    }

    @Test("send multiple signals to local agent")
    func sendMultipleSignalsToLocalAgent() async throws {
        await SignalTracker.shared.reset()

        let actorSystem = SymbioActorSystem()
        let community = Community(actorSystem: actorSystem)

        let member = try await community.spawn {
            TestWorkerAgent(community: community, actorSystem: actorSystem)
        }

        for i in 0..<5 {
            let signal = WorkSignal(task: "task-\(i)", priority: i)
            _ = try await community.send(signal, to: member, perception: "work")
        }

        let count = await SignalTracker.shared.signalCount(for: member.id)
        #expect(count == 5)
    }

    @Test("send to unavailable member throws error")
    func sendToUnavailableMemberThrows() async throws {
        let actorSystem = SymbioActorSystem()
        let community = Community(actorSystem: actorSystem)

        let unavailableMember = Member(
            id: "unavailable",
            name: nil,
            accepts: ["work"],
            provides: [],
            isAvailable: false,
            metadata: ["location": "local"]
        )

        let signal = WorkSignal(task: "test", priority: 0)

        await #expect(throws: CommunityError.self) {
            try await community.send(signal, to: unavailableMember, perception: "work")
        }
    }

    @Test("send with wrong perception throws error")
    func sendWithWrongPerceptionThrows() async throws {
        let actorSystem = SymbioActorSystem()
        let community = Community(actorSystem: actorSystem)

        let member = try await community.spawn {
            TestWorkerAgent(community: community, actorSystem: actorSystem)
        }

        let signal = WorkSignal(task: "test", priority: 0)

        // Member only accepts "work", not "result"
        await #expect(throws: CommunityError.self) {
            try await community.send(signal, to: member, perception: "result")
        }
    }
}

// MARK: - Community Changes Tests

@Suite("Community Changes Tests", .serialized)
struct CommunityChangesTests {

    @Test("spawn emits joined event")
    func spawnEmitsJoinedEvent() async throws {
        let actorSystem = SymbioActorSystem()
        let community = Community(actorSystem: actorSystem)
        let changes = await community.changes

        // Start collecting changes in background
        let collectedChanges = Task {
            var events: [CommunityChange] = []
            for await change in changes {
                events.append(change)
                if events.count >= 1 { break }
            }
            return events
        }

        // Spawn agent
        _ = try await community.spawn {
            TestWorkerAgent(community: community, actorSystem: actorSystem)
        }

        // Give time for event to propagate
        try await Task.sleep(for: .milliseconds(100))

        // Cancel collection
        collectedChanges.cancel()
    }

    @Test("terminate emits left event")
    func terminateEmitsLeftEvent() async throws {
        let actorSystem = SymbioActorSystem()
        let community = Community(actorSystem: actorSystem)
        let changes = await community.changes

        // Spawn first
        let member = try await community.spawn {
            TestWorkerAgent(community: community, actorSystem: actorSystem)
        }

        // Start collecting changes in background
        let collectedChanges = Task {
            var events: [CommunityChange] = []
            for await change in changes {
                events.append(change)
                if events.count >= 2 { break }  // joined + left
            }
            return events
        }

        // Terminate
        try await community.terminate(member)

        // Give time for event to propagate
        try await Task.sleep(for: .milliseconds(100))

        collectedChanges.cancel()
    }
}

// MARK: - Community Lifecycle Tests

@Suite("Community Lifecycle Tests", .serialized)
struct CommunityLifecycleTests {

    @Test("stop terminates all local agents")
    func stopTerminatesAllLocalAgents() async throws {
        await TerminationTracker.shared.reset()

        let actorSystem = SymbioActorSystem()
        let community = Community(actorSystem: actorSystem)

        // Spawn agents
        for _ in 0..<3 {
            _ = try await community.spawn {
                TestWorkerAgent(community: community, actorSystem: actorSystem)
            }
        }

        #expect(await community.members.count == 3)

        // Stop community
        try await community.stop()

        // Members should be removed
        #expect(await community.members.count == 0)
    }

    @Test("stop clears member cache")
    func stopClearsMemberCache() async throws {
        let actorSystem = SymbioActorSystem()
        let community = Community(actorSystem: actorSystem)

        for _ in 0..<3 {
            _ = try await community.spawn {
                TestWorkerAgent(community: community, actorSystem: actorSystem)
            }
        }

        #expect(await community.members.count == 3)

        try await community.stop()

        #expect(await community.members.count == 0)
        #expect(await community.availableMembers.count == 0)
    }
}
