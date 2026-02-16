//
//  TurnGateTests.swift
//  SwiftAgent
//

import Testing
import Foundation
import Synchronization
@testable import SwiftAgent

/// Sendable counter for use across Task boundaries.
private final class AtomicCounter: Sendable {
    private let _value: Mutex<Int> = Mutex(0)

    var value: Int { _value.withLock { $0 } }

    func increment() {
        _value.withLock { $0 += 1 }
    }
}

@Suite("TurnGate Tests")
struct TurnGateTests {

    @Test("waitIfNeeded passes immediately when no turn is active", .timeLimit(.minutes(1)))
    func waitPassesWhenNoTurn() async {
        let gate = TurnGate()
        await gate.waitIfNeeded()
        // If we reach here, the gate did not hang.
    }

    @Test("waitIfNeeded suspends during active turn", .timeLimit(.minutes(1)))
    func waitSuspendsDuringTurn() async {
        let gate = TurnGate()
        gate.enterTurn()

        let resumed = Mutex(false)

        let waiterTask = Task {
            await gate.waitIfNeeded()
            resumed.withLock { $0 = true }
        }

        // Give the waiter time to suspend
        try? await Task.sleep(for: .milliseconds(100))
        #expect(resumed.withLock { $0 } == false)

        // Leave turn should resume the waiter
        gate.leaveTurn()
        _ = await waiterTask.result
        #expect(resumed.withLock { $0 } == true)
    }

    @Test("Multiple waiters are all resumed on leaveTurn", .timeLimit(.minutes(1)))
    func multipleWaitersResumed() async {
        let gate = TurnGate()
        gate.enterTurn()

        let counter = AtomicCounter()

        let tasks = (0..<3).map { _ in
            Task {
                await gate.waitIfNeeded()
                counter.increment()
            }
        }

        // Give waiters time to suspend
        try? await Task.sleep(for: .milliseconds(100))
        #expect(counter.value == 0)

        gate.leaveTurn()

        for task in tasks {
            _ = await task.result
        }
        #expect(counter.value == 3)
    }

    @Test("Gate can be reused across cycles", .timeLimit(.minutes(1)))
    func gateReusable() async {
        let gate = TurnGate()

        // Cycle 1
        gate.enterTurn()
        let resumed1 = Mutex(false)
        let task1 = Task {
            await gate.waitIfNeeded()
            resumed1.withLock { $0 = true }
        }
        try? await Task.sleep(for: .milliseconds(50))
        gate.leaveTurn()
        _ = await task1.result
        #expect(resumed1.withLock { $0 } == true)

        // Cycle 2
        gate.enterTurn()
        let resumed2 = Mutex(false)
        let task2 = Task {
            await gate.waitIfNeeded()
            resumed2.withLock { $0 = true }
        }
        try? await Task.sleep(for: .milliseconds(50))
        gate.leaveTurn()
        _ = await task2.result
        #expect(resumed2.withLock { $0 } == true)
    }
}
