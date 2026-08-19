import Foundation
import NetworkingCore
import SwiftAgent
import SwiftAgentSymbio
@testable import SwiftAgentSymbioAgentAdapter
import Testing

@Suite("Agent participant endpoint")
struct AgentParticipantEndpointTests {
    @Test("Agent shutdown releases work before endpoint drain", .timeLimit(.minutes(1)))
    func shutdownSignalsAgentBeforeDraining() async throws {
        let agent = ShutdownDrivenAgent()
        let endpoint = try AgentParticipantEndpoint(agent: agent)
        let invocation = Task {
            try await endpoint.invoke(SymbioInvocation(
                envelope: SymbioInvocationEnvelope(
                    senderID: "sender.local",
                    recipientID: agent.participantID,
                    capability: "agent.perception.test",
                    representation: .typedPayload(schema: "test"),
                    arguments: OwnedBytes(consuming: Array("request".utf8)),
                    executionBudget: .seconds(30)
                ),
                principal: .local(ParticipantDescriptor(
                    id: "sender.local",
                    kind: .agent
                ))
            ))
        }
        await agent.waitUntilReceiveStarts()

        let shutdown = Task {
            await endpoint.shutdown()
        }
        await agent.waitUntilShutdownStarts()

        let result = try await invocation.value
        await shutdown.value
        #expect(result == OwnedBytes(consuming: Array("released".utf8)))
        #expect(await agent.shutdownCount() == 1)
    }
}

private struct TestPerception: Perception {
    typealias Signal = Data

    let identifier = "test"
}

private actor ShutdownDrivenAgent: CommunicableAgent, AgentShutdownHandling {
    nonisolated let participantID: ParticipantID = "receiver.local"
    nonisolated let displayName: String? = "Receiver"
    nonisolated let perceptions: [any Perception] = [TestPerception()]

    private var receiveContinuation: CheckedContinuation<Data?, any Error>?
    private var receiveStarted = false
    private var receiveStartWaiters: [CheckedContinuation<Void, Never>] = []
    private var shutdownStarted = false
    private var shutdownStartWaiters: [CheckedContinuation<Void, Never>] = []
    private var shutdowns = 0

    func receive(_ data: Data, perception: String) async throws -> Data? {
        receiveStarted = true
        let waiters = receiveStartWaiters
        receiveStartWaiters.removeAll()
        for waiter in waiters {
            waiter.resume()
        }
        return try await withCheckedThrowingContinuation { continuation in
            receiveContinuation = continuation
        }
    }

    func shutdown() async {
        shutdowns += 1
        shutdownStarted = true
        let waiters = shutdownStartWaiters
        shutdownStartWaiters.removeAll()
        for waiter in waiters {
            waiter.resume()
        }
        let continuation = receiveContinuation
        receiveContinuation = nil
        continuation?.resume(returning: Data("released".utf8))
    }

    func waitUntilReceiveStarts() async {
        guard !receiveStarted else { return }
        await withCheckedContinuation { continuation in
            receiveStartWaiters.append(continuation)
        }
    }

    func waitUntilShutdownStarts() async {
        guard !shutdownStarted else { return }
        await withCheckedContinuation { continuation in
            shutdownStartWaiters.append(continuation)
        }
    }

    func shutdownCount() -> Int {
        shutdowns
    }
}
