import Testing
import Foundation
@testable import SwiftAgent

// MARK: - Test Helpers

/// A step that returns after a delay
struct TimedStep: Step, Sendable {
    let delay: Duration
    let result: Int

    func run(_ input: Int) async throws -> Int {
        try await Task.sleep(for: delay)
        return result
    }
}

/// A step that fails after a delay
struct DelayedFailingStep: Step, Sendable {
    let delay: Duration
    struct StepError: Error {}

    func run(_ input: Int) async throws -> Int {
        try await Task.sleep(for: delay)
        throw StepError()
    }
}

/// A step that returns immediately
struct ImmediateStep: Step, Sendable {
    let result: Int

    func run(_ input: Int) async throws -> Int {
        result
    }
}

// MARK: - Race Tests

@Suite("Race Tests")
struct RaceTests {

    @Test("Race returns first successful result")
    func raceReturnsFirst() async throws {
        let race = Race<Int, Int> {
            TimedStep(delay: .milliseconds(100), result: 100)
            TimedStep(delay: .milliseconds(10), result: 10)
            TimedStep(delay: .milliseconds(50), result: 50)
        }

        let result = try await race.run(0)
        #expect(result == 10) // Fastest step wins
    }

    @Test("Race with single step")
    func raceSingleStep() async throws {
        let race = Race<Int, Int> {
            ImmediateStep(result: 42)
        }

        let result = try await race.run(0)
        #expect(result == 42)
    }

    @Test("Race returns faster step even with slower ones")
    func raceFasterStepWins() async throws {
        let startTime = Date()

        let race = Race<Int, Int> {
            TimedStep(delay: .milliseconds(200), result: 200)
            ImmediateStep(result: 1)
        }

        let result = try await race.run(0)
        let elapsed = Date().timeIntervalSince(startTime)

        #expect(result == 1)
        // Should complete much faster than the slow step (200ms)
        // Allow 100ms for system overhead
        #expect(elapsed < 0.1)
    }

    @Test("Race succeeds if at least one step succeeds")
    func raceSucceedsWithOneSuccess() async throws {
        let race = Race<Int, Int> {
            DelayedFailingStep(delay: .milliseconds(10))
            ImmediateStep(result: 42)
        }

        let result = try await race.run(0)
        #expect(result == 42)
    }

    @Test("Race throws if all steps fail")
    func raceThrowsWhenAllFail() async throws {
        let race = Race<Int, Int> {
            DelayedFailingStep(delay: .milliseconds(10))
            DelayedFailingStep(delay: .milliseconds(20))
        }

        await #expect(throws: DelayedFailingStep.StepError.self) {
            try await race.run(0)
        }
    }
}

// MARK: - Race with Timeout Tests

@Suite("Race Timeout Tests")
struct RaceTimeoutTests {

    @Test("Race with timeout succeeds when step finishes in time")
    func raceWithTimeoutSucceeds() async throws {
        let race = Race<Int, Int>(timeout: .milliseconds(100)) {
            TimedStep(delay: .milliseconds(20), result: 42)
        }

        let result = try await race.run(0)
        #expect(result == 42)
    }

    @Test("Race with timeout fails when step takes too long")
    func raceWithTimeoutFails() async throws {
        let race = Race<Int, Int>(timeout: .milliseconds(10)) {
            TimedStep(delay: .milliseconds(200), result: 42)
        }

        await #expect(throws: RaceError.self) {
            try await race.run(0)
        }
    }

    @Test("Race timeout returns faster step before timeout")
    func raceTimeoutReturnsFasterStep() async throws {
        let race = Race<Int, Int>(timeout: .milliseconds(100)) {
            TimedStep(delay: .milliseconds(200), result: 200)
            ImmediateStep(result: 1)
        }

        let result = try await race.run(0)
        #expect(result == 1)
    }
}

// MARK: - RaceError Tests

@Suite("RaceError Tests")
struct RaceErrorTests {

    @Test("RaceError.noSuccessfulResults exists")
    func noSuccessfulResultsError() {
        let error = RaceError.noSuccessfulResults
        #expect(error == .noSuccessfulResults)
    }

    @Test("RaceError.timeout exists")
    func timeoutError() {
        let error = RaceError.timeout
        #expect(error == .timeout)
    }
}

// MARK: - Race Cancellation Tests

@Suite("Race Cancellation Tests")
struct RaceCancellationTests {

    @Test("Race returns immediately when fast step wins")
    func raceReturnsImmediately() async throws {
        let startTime = Date()

        let race = Race<Int, Int> {
            ImmediateStep(result: 1)
            TimedStep(delay: .milliseconds(100), result: 100)
        }

        let result = try await race.run(0)
        let elapsed = Date().timeIntervalSince(startTime)

        #expect(result == 1)
        // Should complete much faster than the slow step (100ms)
        // Allow 80ms for system overhead
        #expect(elapsed < 0.08)

        // Give some time for cancellation to propagate
        try await Task.sleep(for: .milliseconds(50))
    }
}
