//
//  AgentSessionTests.swift
//  SwiftAgent
//

import Testing
import Foundation
import Synchronization
@testable import SwiftAgent

#if OpenFoundationModels
import OpenFoundationModels

// MARK: - AgentSession Tests

@Suite("AgentSession Tests")
struct AgentSessionTests {

    @Test("Input failures terminate the session", .timeLimit(.minutes(1)))
    func inputFailureTerminatesSession() async throws {
        let connection = MockConnection()
        let session = AgentSession(connection: connection)
        connection.failInput("input failed")

        await #expect(throws: MockConnectionError.self) {
            try await session.run(model: MockLanguageModel()) {
                Instructions("Echo")
            } step: {
                Transform { (input: Prompt) in "unused" }
            }
        }
    }

    @Test("Unexpected input cancellation terminates the session", .timeLimit(.minutes(1)))
    func unexpectedInputCancellationTerminatesSession() async throws {
        let connection = MockConnection()
        let session = AgentSession(connection: connection)
        connection.cancelInputUnexpectedly()

        await #expect(throws: CancellationError.self) {
            try await session.run(model: MockLanguageModel()) {
                Instructions("Echo")
            } step: {
                Transform { (_: Prompt) in "unused" }
            }
        }
    }

    @Test("Input failure cancels the active turn", .timeLimit(.minutes(1)))
    func inputFailureCancelsActiveTurn() async throws {
        let connection = MockConnection()
        let session = AgentSession(connection: connection)
        let turnStarted = OneShotSignal()
        let invocationCount = InvocationCount()
        connection.enqueue(RunRequest(input: .text("Hello")))
        connection.enqueue(RunRequest(input: .text("Must not start")))

        let run = Task {
            try await session.run(model: MockLanguageModel()) {
                Instructions("Wait")
            } step: {
                Transform { (input: Prompt) in
                    await invocationCount.increment()
                    await turnStarted.signal()
                    guard let token = TurnCancellationContext.current else {
                        return "missing cancellation context"
                    }
                    _ = await token.waitForCancellation()
                    try token.checkCancellation()
                    return "unreachable"
                }
            }
        }
        await turnStarted.wait()
        connection.failInput("input failed during turn")

        await #expect(throws: MockConnectionError.self) {
            try await run.value
        }
        #expect(await invocationCount.value == 1)
    }

    @Test("Event delivery failures terminate the session", .timeLimit(.minutes(1)))
    func eventDeliveryFailureTerminatesSession() async throws {
        let connection = MockConnection()
        let session = AgentSession(connection: connection)
        connection.failOutput("output failed")
        connection.enqueueAndFinish(RunRequest(input: .text("Hello")))

        await #expect(throws: AgentSessionError.self) {
            try await session.run(model: MockLanguageModel()) {
                Instructions("Echo")
            } step: {
                Transform { (input: Prompt) in "unused" }
            }
        }
    }

    @Test("Text request produces runStarted and runCompleted events", .timeLimit(.minutes(1)))
    func textRequestProducesEvents() async throws {
        let transport = MockConnection()
        let session = AgentSession(connection: transport)

        transport.enqueueAndFinish(RunRequest(input: .text("Hello")))

        try await session.run(model: MockLanguageModel()) {
            Instructions("Echo")
        } step: {
            Transform { (input: Prompt) in "Echo response" }
        }

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
        let transport = MockConnection()
        let session = AgentSession(connection: transport)

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

        try await session.run(model: MockLanguageModel()) {
            Instructions("Slow")
        } step: {
            Transform { (input: Prompt) in
                for _ in 0..<50 {
                    try TurnCancellationContext.current?.checkCancellation()
                    try await Task.sleep(for: .milliseconds(100))
                }
                return "done"
            }
        }

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
        let transport = MockConnection()
        let session = AgentSession(connection: transport)

        let turnID = UUID().uuidString

        // Send the same turnID twice — the second should be skipped by completedTurns guard
        transport.enqueue(RunRequest(turnID: turnID, input: .text("First")))
        transport.enqueue(RunRequest(turnID: turnID, input: .text("Duplicate")))
        transport.finishInput()

        try await session.run(model: MockLanguageModel()) {
            Instructions("Echo")
        } step: {
            Transform { (input: Prompt) in "Echo response" }
        }

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
        let transport = MockConnection(supportsConcurrentReceive: false)
        let session = AgentSession(connection: transport)

        transport.enqueueAndFinish(RunRequest(input: .text("Hello")))

        try await session.run(model: MockLanguageModel()) {
            Instructions("Echo")
        } step: {
            Transform { (input: Prompt) in "Echo response" }
        }

        let events = transport.collectedEvents
        let hasRunCompleted = events.contains { event in
            if case .runCompleted(let completed) = event {
                return completed.status == .completed
            }
            return false
        }

        #expect(hasRunCompleted)
    }

    @Test("A session consumes its connection exactly once", .timeLimit(.minutes(1)))
    func sessionConsumesConnectionOnce() async throws {
        let connection = MockConnection()
        let session = AgentSession(connection: connection)
        connection.finishInput()

        try await session.run(model: MockLanguageModel()) {
            Instructions("Echo")
        } step: {
            Transform { (_: Prompt) in "unused" }
        }

        await #expect(throws: AgentSessionError.self) {
            try await session.run(model: MockLanguageModel()) {
                Instructions("Echo")
            } step: {
                Transform { (_: Prompt) in "unused" }
            }
        }
    }

    @Test("Connection approval requires concurrent receive")
    func connectionApprovalRequiresConcurrentReceive() async {
        let connection = MockConnection(supportsConcurrentReceive: false)
        let session = AgentSession(
            connection: connection,
            approvalHandler: ConnectionApprovalHandler()
        )

        await #expect(throws: AgentSessionError.self) {
            try await session.run(model: MockLanguageModel()) {
                Instructions("Echo")
            } step: {
                Transform { (_: Prompt) in "unused" }
            }
        }
    }

    @Test("Independent stdin readers are rejected for gated connections")
    func independentStdinReaderIsRejected() async {
        let connection = MockConnection(supportsConcurrentReceive: false)
        let session = AgentSession(
            connection: connection,
            approvalHandler: CLIPermissionHandler(output: { _ in })
        )

        await #expect(throws: AgentSessionError.self) {
            try await session.run(model: MockLanguageModel()) {
                Instructions("Echo")
            } step: {
                Transform { (_: Prompt) in "unused" }
            }
        }
    }

    // MARK: - TurnID Matching Tests

    @Test("Cross-turn cancel does not affect unrelated turn", .timeLimit(.minutes(1)))
    func crossTurnCancelDoesNotAffectUnrelatedTurn() async throws {
        let transport = MockConnection()
        let session = AgentSession(connection: transport)

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

        try await session.run(model: MockLanguageModel()) {
            Instructions("Slow")
        } step: {
            Transform { (input: Prompt) in
                for _ in 0..<50 {
                    try TurnCancellationContext.current?.checkCancellation()
                    try await Task.sleep(for: .milliseconds(100))
                }
                return "done"
            }
        }

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
        let transport = MockConnection()
        let session = AgentSession(connection: transport)

        let turnID = UUID().uuidString

        // Cancel arrives BEFORE the text request
        transport.enqueue(RunRequest(turnID: turnID, input: .cancel))
        transport.enqueue(RunRequest(turnID: turnID, input: .text("Hello")))
        transport.finishInput()

        try await session.run(model: MockLanguageModel()) {
            Instructions("Slow")
        } step: {
            Transform { (input: Prompt) in
                for _ in 0..<50 {
                    try TurnCancellationContext.current?.checkCancellation()
                    try await Task.sleep(for: .milliseconds(100))
                }
                return "done"
            }
        }

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
        let transport = MockConnection()
        let session = AgentSession(connection: transport)

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

        try await session.run(model: MockLanguageModel()) {
            Instructions("Echo")
        } step: {
            Transform { (input: Prompt) in "Echo response" }
        }

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
        let transport = MockConnection()
        let session = AgentSession(connection: transport)

        let realTurnID = UUID().uuidString
        let fakeTurnID = UUID().uuidString

        // Cancel for a turn that never exists
        transport.enqueue(RunRequest(turnID: fakeTurnID, input: .cancel))
        // Real turn should proceed normally
        transport.enqueue(RunRequest(turnID: realTurnID, input: .text("Hello")))
        transport.finishInput()

        try await session.run(model: MockLanguageModel()) {
            Instructions("Echo")
        } step: {
            Transform { (input: Prompt) in "Echo response" }
        }

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
        let transport = MockConnection()
        let session = AgentSession(connection: transport)

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

        try await session.run(model: MockLanguageModel()) {
            Instructions("CancellationAware")
        } step: {
            Transform { (input: Prompt) in
                try TurnCancellationContext.current?.checkCancellation()
                return "Done"
            }
        }

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
        let transport = MockConnection()
        let session = AgentSession(connection: transport)

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

        try await session.run(model: MockLanguageModel()) {
            Instructions("Slow")
        } step: {
            Transform { (input: Prompt) in
                for _ in 0..<50 {
                    try TurnCancellationContext.current?.checkCancellation()
                    try await Task.sleep(for: .milliseconds(100))
                }
                return "done"
            }
        }

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
        // No connectionApprovalHandler configured
        let transport = MockConnection()
        let session = AgentSession(connection: transport)

        let turnID = UUID().uuidString

        // Send approval response first (turnID not yet completed, passes idempotency check),
        // then a text request so the session can shut down.
        let approval = ApprovalResponse(approvalID: "test-approval", decision: .allowOnce)
        transport.enqueue(RunRequest(turnID: turnID, input: .approvalResponse(approval)))
        transport.enqueueAndFinish(RunRequest(input: .text("Hello")))

        try await session.run(model: MockLanguageModel()) {
            Instructions("Echo")
        } step: {
            Transform { (input: Prompt) in "Echo response" }
        }

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

private actor OneShotSignal {
    private var isSignalled = false
    private var waiters: [CheckedContinuation<Void, Never>] = []

    func signal() {
        guard !isSignalled else {
            return
        }
        isSignalled = true
        let waiters = self.waiters
        self.waiters.removeAll()
        for waiter in waiters {
            waiter.resume()
        }
    }

    func wait() async {
        guard !isSignalled else {
            return
        }
        await withCheckedContinuation { continuation in
            if isSignalled {
                continuation.resume()
            } else {
                waiters.append(continuation)
            }
        }
    }
}

private actor InvocationCount {
    private(set) var value = 0

    func increment() {
        value += 1
    }
}

#endif
