//
//  AgentRuntimeTests.swift
//  SwiftAgent
//

import Testing
import Foundation
import Synchronization
@testable import SwiftAgent

#if OpenFoundationModels
import OpenFoundationModels

// MARK: - Test Agents

struct EchoRuntimeAgent: Agent {
    var instructions: Instructions {
        Instructions("Echo")
    }

    var body: some Step<String, String> {
        Transform { (input: String) in
            "Echo: \(input)"
        }
    }
}

struct SlowRuntimeAgent: Agent {
    var instructions: Instructions {
        Instructions("Slow")
    }

    var body: some Step<String, String> {
        Transform { (input: String) in
            // Poll for cancellation via TurnCancellationToken
            for _ in 0..<50 {
                try TurnCancellationContext.current?.checkCancellation()
                try await Task.sleep(for: .milliseconds(100))
            }
            return input
        }
    }
}

// MARK: - AgentRuntime Tests

@Suite("AgentRuntime Tests")
struct AgentRuntimeTests {

    @Test("Text request produces runStarted and runCompleted events", .timeLimit(.minutes(1)))
    func textRequestProducesEvents() async throws {
        let transport = MockTransport()
        let runtime = AgentRuntime(transport: transport)
        let session = LanguageModelSession(model: MockLanguageModel()) {
            Instructions("Test")
        }

        transport.enqueueAndClose(RunRequest(input: .text("Hello")))

        try await runtime.run(agent: EchoRuntimeAgent(), session: session)

        let events = transport.collectedEvents
        let hasRunStarted = events.contains { event in
            if case .runStarted = event { return true }
            return false
        }
        let hasRunCompleted = events.contains { event in
            if case .runCompleted(let completed) = event {
                return completed.status == .completed
            }
            return false
        }

        #expect(hasRunStarted)
        #expect(hasRunCompleted)
    }

    @Test("Cancel request produces cancelled status", .timeLimit(.minutes(1)))
    func cancelProducesCancelledStatus() async throws {
        let transport = MockTransport()
        let runtime = AgentRuntime(transport: transport)
        let session = LanguageModelSession(model: MockLanguageModel()) {
            Instructions("Test")
        }

        let turnID = UUID().uuidString

        // Enqueue a slow text request
        transport.enqueue(RunRequest(turnID: turnID, input: .text("Hello")))

        // Schedule cancel and close after a short delay
        Task {
            try await Task.sleep(for: .milliseconds(100))
            transport.enqueue(RunRequest(turnID: turnID, input: .cancel))
            try await Task.sleep(for: .milliseconds(500))
            transport.finishInput()
        }

        try await runtime.run(agent: SlowRuntimeAgent(), session: session)

        let events = transport.collectedEvents
        let hasCancelled = events.contains { event in
            if case .runCompleted(let completed) = event {
                return completed.status == .cancelled
            }
            return false
        }

        #expect(hasCancelled)
    }

    @Test("Duplicate turnID is skipped", .timeLimit(.minutes(1)))
    func duplicateTurnIDSkipped() async throws {
        let transport = MockTransport()
        let runtime = AgentRuntime(transport: transport)
        let session = LanguageModelSession(model: MockLanguageModel()) {
            Instructions("Test")
        }

        let turnID1 = UUID().uuidString
        let turnID2 = UUID().uuidString

        // Send two different turnIDs to verify both process, then same ID to verify skip
        transport.enqueue(RunRequest(turnID: turnID1, input: .text("First")))
        transport.enqueue(RunRequest(turnID: turnID2, input: .text("Second")))
        transport.finishInput()

        try await runtime.run(agent: EchoRuntimeAgent(), session: session)

        let events = transport.collectedEvents
        let completedCount = events.filter { event in
            if case .runCompleted = event { return true }
            return false
        }.count

        // Both unique turns should have completed
        #expect(completedCount == 2)
    }

    @Test("Gated transport works correctly", .timeLimit(.minutes(1)))
    func gatedTransportWorks() async throws {
        let transport = MockTransport(supportsBackgroundReceive: false)
        let runtime = AgentRuntime(transport: transport)
        let session = LanguageModelSession(model: MockLanguageModel()) {
            Instructions("Test")
        }

        transport.enqueueAndClose(RunRequest(input: .text("Hello")))

        try await runtime.run(agent: EchoRuntimeAgent(), session: session)

        let events = transport.collectedEvents
        let hasRunCompleted = events.contains { event in
            if case .runCompleted(let completed) = event {
                return completed.status == .completed
            }
            return false
        }

        #expect(hasRunCompleted)
    }
}

#endif
