//
//  TurnCancellationTokenTests.swift
//  SwiftAgent
//

import Testing
import Foundation
@testable import SwiftAgent

@Suite("TurnCancellationToken Tests")
struct TurnCancellationTokenTests {

    @Test("Initial state is not cancelled")
    func initialStateNotCancelled() {
        let token = TurnCancellationToken()
        #expect(token.isCancelled == false)
    }

    @Test("cancel() sets isCancelled to true")
    func cancelSetsCancelled() {
        let token = TurnCancellationToken()
        token.cancel()
        #expect(token.isCancelled == true)
    }

    @Test("checkCancellation() throws when cancelled")
    func checkCancellationThrowsWhenCancelled() {
        let token = TurnCancellationToken()
        token.cancel()
        #expect(throws: CancellationError.self) {
            try token.checkCancellation()
        }
    }

    @Test("checkCancellation() does not throw when not cancelled")
    func checkCancellationNoThrowWhenNotCancelled() throws {
        let token = TurnCancellationToken()
        try token.checkCancellation()
    }

    @Test("cancel() is idempotent")
    func cancelIsIdempotent() {
        let token = TurnCancellationToken()
        token.cancel()
        token.cancel()
        #expect(token.isCancelled == true)
    }

    @Test("The first cancellation reason wins")
    func firstCancellationReasonWins() {
        let token = TurnCancellationToken()
        token.cancel()
        token.cancelForTimeout(.seconds(1))

        guard let requestedReason = token.cancellationReason,
              case .requested = requestedReason else {
            Issue.record("A later timeout replaced the requested cancellation")
            return
        }

        let timeoutToken = TurnCancellationToken()
        timeoutToken.cancelForTimeout(.seconds(1))
        timeoutToken.cancel()
        guard let timeoutReason = timeoutToken.cancellationReason,
              case .timedOut(let duration) = timeoutReason else {
            Issue.record("A later request replaced the timeout cancellation")
            return
        }
        #expect(duration == .seconds(1))
    }

    @Test("Operation settlement rejects later cancellation")
    func operationSettlementRejectsLaterCancellation() {
        let token = TurnCancellationToken()
        let completedAt = ContinuousClock.now

        let terminal = token.settleOperation(
            completedAt: completedAt,
            deadline: nil,
            timeout: nil
        )
        token.cancel()

        guard case .operationCompleted = terminal else {
            Issue.record("The operation did not own the terminal transition")
            return
        }
        #expect(!token.isCancelled)
    }

    @Test("Cancellation rejects later operation settlement")
    func cancellationRejectsLaterOperationSettlement() {
        let token = TurnCancellationToken()
        token.cancel()

        let terminal = token.settleOperation(
            completedAt: ContinuousClock.now,
            deadline: nil,
            timeout: nil
        )

        guard case .cancelled(.requested) = terminal else {
            Issue.record("A later operation completion replaced cancellation")
            return
        }
    }

    @Test("Completion at the deadline is timed out")
    func completionAtDeadlineIsTimedOut() {
        let token = TurnCancellationToken()
        let deadline = ContinuousClock.now

        let terminal = token.settleOperation(
            completedAt: deadline,
            deadline: deadline,
            timeout: .seconds(1)
        )

        guard case .cancelled(.timedOut(let duration)) = terminal else {
            Issue.record("Deadline equality did not settle as a timeout")
            return
        }
        #expect(duration == .seconds(1))
    }

    @Test("Cancellation resumes asynchronous waiters", .timeLimit(.minutes(1)))
    func cancellationResumesWaiters() async {
        let token = TurnCancellationToken()
        let waiter = Task {
            await token.waitForCancellation()
        }
        await Task.yield()

        token.cancel()

        let reason = await waiter.value
        if case .requested = reason {
            // Expected.
        } else {
            Issue.record("Cancellation waiter returned the wrong reason")
        }
    }

    @Test("Cancelling an observer does not cancel the token", .timeLimit(.minutes(1)))
    func cancellingObserverDoesNotCancelToken() async {
        let token = TurnCancellationToken()
        let waiter = Task {
            await token.waitForCancellation()
        }
        await Task.yield()

        waiter.cancel()
        _ = await waiter.value

        #expect(!token.isCancelled)
    }

    @Test("Context propagation via withValue", .timeLimit(.minutes(1)))
    func contextPropagation() async throws {
        let token = TurnCancellationToken()

        let retrieved = await TurnCancellationContext.withValue(token) {
            TurnCancellationContext.current
        }

        #expect(retrieved === token)
    }

    @Test("Context default is nil")
    func contextDefaultIsNil() {
        let current = TurnCancellationContext.current
        #expect(current == nil)
    }
}
