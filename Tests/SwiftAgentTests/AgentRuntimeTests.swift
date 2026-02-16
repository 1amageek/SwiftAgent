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

/// An agent that checks cancellation once at the start, then returns immediately.
/// Pre-emptive cancel → .cancelled; no cancel → .completed (instantly).
struct CancellationAwareAgent: Agent {
    var instructions: Instructions {
        Instructions("CancellationAware")
    }

    var body: some Step<String, String> {
        Transform { (input: String) in
            try TurnCancellationContext.current?.checkCancellation()
            return "Done: \(input)"
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

        let turnID = UUID().uuidString

        // Send the same turnID twice — the second should be skipped by completedTurns guard
        transport.enqueue(RunRequest(turnID: turnID, input: .text("First")))
        transport.enqueue(RunRequest(turnID: turnID, input: .text("Duplicate")))
        transport.finishInput()

        try await runtime.run(agent: EchoRuntimeAgent(), session: session)

        let events = transport.collectedEvents
        let completedCount = events.filter { event in
            if case .runCompleted(let completed) = event {
                return completed.turnID == turnID
            }
            return false
        }.count

        // Only the first request should produce a runCompleted event
        #expect(completedCount == 1, "Duplicate turnID should be skipped, producing only one runCompleted")
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

    // MARK: - TurnID Matching Tests

    @Test("Cross-turn cancel does not affect unrelated turn", .timeLimit(.minutes(1)))
    func crossTurnCancelDoesNotAffectUnrelatedTurn() async throws {
        let transport = MockTransport()
        let runtime = AgentRuntime(transport: transport)
        let session = LanguageModelSession(model: MockLanguageModel()) {
            Instructions("Test")
        }

        let turnA = UUID().uuidString
        let turnB = UUID().uuidString

        // Enqueue slow Turn B, then cancel for Turn A (which is not running)
        transport.enqueue(RunRequest(turnID: turnB, input: .text("Hello")))

        Task {
            try await Task.sleep(for: .milliseconds(100))
            // Cancel Turn A — Turn B should NOT be affected
            transport.enqueue(RunRequest(turnID: turnA, input: .cancel))
            try await Task.sleep(for: .milliseconds(500))
            transport.finishInput()
        }

        try await runtime.run(agent: SlowRuntimeAgent(), session: session)

        let events = transport.collectedEvents
        // Turn B should complete normally (not cancelled)
        let hasCancelled = events.contains { event in
            if case .runCompleted(let completed) = event {
                return completed.turnID == turnB && completed.status == .cancelled
            }
            return false
        }
        let hasCompleted = events.contains { event in
            if case .runCompleted(let completed) = event {
                return completed.turnID == turnB && completed.status == .completed
            }
            return false
        }

        #expect(!hasCancelled, "Turn B should NOT be cancelled by Turn A's cancel")
        #expect(hasCompleted, "Turn B should complete normally")
    }

    @Test("Pre-emptive cancel before turn starts produces cancelled status", .timeLimit(.minutes(1)))
    func preemptiveCancelProducesCancelledStatus() async throws {
        let transport = MockTransport()
        let runtime = AgentRuntime(transport: transport)
        let session = LanguageModelSession(model: MockLanguageModel()) {
            Instructions("Test")
        }

        let turnID = UUID().uuidString

        // Cancel arrives BEFORE the text request
        transport.enqueue(RunRequest(turnID: turnID, input: .cancel))
        transport.enqueue(RunRequest(turnID: turnID, input: .text("Hello")))
        transport.finishInput()

        try await runtime.run(agent: SlowRuntimeAgent(), session: session)

        let events = transport.collectedEvents
        let hasCancelled = events.contains { event in
            if case .runCompleted(let completed) = event {
                return completed.turnID == turnID && completed.status == .cancelled
            }
            return false
        }

        #expect(hasCancelled, "Pre-emptive cancel should produce cancelled status")
    }

    @Test("Cancel for completed turn is harmless", .timeLimit(.minutes(1)))
    func cancelForCompletedTurnIsHarmless() async throws {
        let transport = MockTransport()
        let runtime = AgentRuntime(transport: transport)
        let session = LanguageModelSession(model: MockLanguageModel()) {
            Instructions("Test")
        }

        let turnID = UUID().uuidString

        // Enqueue a fast text request, then a late cancel, then close
        transport.enqueue(RunRequest(turnID: turnID, input: .text("Hello")))

        Task {
            // Wait for the fast turn to complete
            try await Task.sleep(for: .milliseconds(300))
            // Cancel arrives after turn is already completed
            transport.enqueue(RunRequest(turnID: turnID, input: .cancel))
            try await Task.sleep(for: .milliseconds(100))
            transport.finishInput()
        }

        try await runtime.run(agent: EchoRuntimeAgent(), session: session)

        let events = transport.collectedEvents
        let hasCompleted = events.contains { event in
            if case .runCompleted(let completed) = event {
                return completed.turnID == turnID && completed.status == .completed
            }
            return false
        }
        let hasCancelled = events.contains { event in
            if case .runCompleted(let completed) = event {
                return completed.turnID == turnID && completed.status == .cancelled
            }
            return false
        }

        #expect(hasCompleted, "Turn should have completed normally")
        #expect(!hasCancelled, "Late cancel should not produce cancelled status")
    }

    @Test("Cancel for nonexistent turn is harmless", .timeLimit(.minutes(1)))
    func cancelForNonexistentTurnIsHarmless() async throws {
        let transport = MockTransport()
        let runtime = AgentRuntime(transport: transport)
        let session = LanguageModelSession(model: MockLanguageModel()) {
            Instructions("Test")
        }

        let realTurnID = UUID().uuidString
        let fakeTurnID = UUID().uuidString

        // Cancel for a turn that never exists
        transport.enqueue(RunRequest(turnID: fakeTurnID, input: .cancel))
        // Real turn should proceed normally
        transport.enqueue(RunRequest(turnID: realTurnID, input: .text("Hello")))
        transport.finishInput()

        try await runtime.run(agent: EchoRuntimeAgent(), session: session)

        let events = transport.collectedEvents
        let hasCompleted = events.contains { event in
            if case .runCompleted(let completed) = event {
                return completed.turnID == realTurnID && completed.status == .completed
            }
            return false
        }

        #expect(hasCompleted, "Real turn should complete normally despite nonexistent cancel")
    }

    @Test("Late cancel after cancelled turn does not poison retry", .timeLimit(.minutes(1)))
    func lateCancelDoesNotPoisonRetry() async throws {
        let transport = MockTransport()
        let runtime = AgentRuntime(transport: transport)
        let session = LanguageModelSession(model: MockLanguageModel()) {
            Instructions("Test")
        }

        let turnID = UUID().uuidString

        // 1. Pre-emptive cancel → first attempt will be immediately cancelled
        transport.enqueue(RunRequest(turnID: turnID, input: .cancel))
        transport.enqueue(RunRequest(turnID: turnID, input: .text("First")))

        Task {
            // Wait for first attempt to process (instant cancellation)
            try await Task.sleep(for: .milliseconds(200))
            // 2. Late stale cancel (absorbed by sentinel token from step 1)
            transport.enqueue(RunRequest(turnID: turnID, input: .cancel))
            try await Task.sleep(for: .milliseconds(100))
            // 3. Retry with same turnID — should NOT be poisoned
            transport.enqueue(RunRequest(turnID: turnID, input: .text("Retry")))
            try await Task.sleep(for: .milliseconds(200))
            transport.finishInput()
        }

        try await runtime.run(agent: CancellationAwareAgent(), session: session)

        let events = transport.collectedEvents
        let completedStatuses = events.compactMap { event -> RunStatus? in
            if case .runCompleted(let completed) = event, completed.turnID == turnID {
                return completed.status
            }
            return nil
        }

        // First attempt: cancelled, second attempt (retry): completed
        #expect(completedStatuses.count == 2, "Should have two runCompleted events")
        #expect(completedStatuses[0] == .cancelled, "First attempt should be cancelled")
        #expect(completedStatuses[1] == .completed, "Retry should complete normally, not poisoned by late cancel")
    }

    @Test("Duplicate cancel for same turn is idempotent", .timeLimit(.minutes(1)))
    func duplicateCancelIsIdempotent() async throws {
        let transport = MockTransport()
        let runtime = AgentRuntime(transport: transport)
        let session = LanguageModelSession(model: MockLanguageModel()) {
            Instructions("Test")
        }

        let turnID = UUID().uuidString

        // Enqueue slow turn, then send cancel twice
        transport.enqueue(RunRequest(turnID: turnID, input: .text("Hello")))

        Task {
            try await Task.sleep(for: .milliseconds(100))
            transport.enqueue(RunRequest(turnID: turnID, input: .cancel))
            transport.enqueue(RunRequest(turnID: turnID, input: .cancel))
            try await Task.sleep(for: .milliseconds(500))
            transport.finishInput()
        }

        try await runtime.run(agent: SlowRuntimeAgent(), session: session)

        let events = transport.collectedEvents
        let cancelledCount = events.filter { event in
            if case .runCompleted(let completed) = event {
                return completed.turnID == turnID && completed.status == .cancelled
            }
            return false
        }.count

        #expect(cancelledCount == 1, "Duplicate cancels should produce exactly one cancelled event")
    }

    // MARK: - Approval Handler Tests

    @Test("Approval response without handler emits warning", .timeLimit(.minutes(1)))
    func approvalResponseWithoutHandlerEmitsWarning() async throws {
        // No transportApprovalHandler configured
        let transport = MockTransport()
        let runtime = AgentRuntime(transport: transport)
        let session = LanguageModelSession(model: MockLanguageModel()) {
            Instructions("Test")
        }

        let turnID = UUID().uuidString

        // Send approval response first (turnID not yet completed, passes idempotency check),
        // then a text request so the runtime can shut down.
        let approval = ApprovalResponse(approvalID: "test-approval", decision: .allowOnce)
        transport.enqueue(RunRequest(turnID: turnID, input: .approvalResponse(approval)))
        transport.enqueueAndClose(RunRequest(input: .text("Hello")))

        try await runtime.run(agent: EchoRuntimeAgent(), session: session)

        let events = transport.collectedEvents
        let hasWarning = events.contains { event in
            if case .warning(let warning) = event {
                return warning.code == "APPROVAL_HANDLER_MISSING"
            }
            return false
        }

        #expect(hasWarning, "Should emit non-fatal warning when approval response has no handler")
    }
}

#endif
