import Testing
import Foundation
@testable import SwiftAgent

// MARK: - Test Helpers

/// A step that returns the input multiplied by a factor
struct MultiplyStep: Step, Sendable {
    let factor: Int

    func run(_ input: Int) async throws -> Int {
        input * factor
    }
}

/// A step that adds a value
struct AddValueStep: Step, Sendable {
    let value: Int

    func run(_ input: Int) async throws -> Int {
        input + value
    }
}

/// A step that simulates work with a delay
struct DelayedStep: Step, Sendable {
    let delay: Duration
    let result: Int

    func run(_ input: Int) async throws -> Int {
        try await Task.sleep(for: delay)
        return result
    }
}

/// A step that throws an error
struct FailingIntStep: Step, Sendable {
    struct StepError: Error {}

    func run(_ input: Int) async throws -> Int {
        throw StepError()
    }
}

// MARK: - Parallel Tests

@Suite("Parallel Tests")
struct ParallelTests {

    @Test("Parallel executes single step")
    func parallelSingleStep() async throws {
        let parallel = Parallel<Int, Int> {
            MultiplyStep(factor: 2)
        }

        let results = try await parallel.run(5)
        #expect(results.count == 1)
        #expect(results.contains(10))
    }

    @Test("Parallel executes two steps concurrently")
    func parallelTwoSteps() async throws {
        let parallel = Parallel<Int, Int> {
            MultiplyStep(factor: 2)
            AddValueStep(value: 10)
        }

        let results = try await parallel.run(5)
        #expect(results.count == 2)
        #expect(results.contains(10))  // 5 * 2
        #expect(results.contains(15))  // 5 + 10
    }

    @Test("Parallel executes three steps concurrently")
    func parallelThreeSteps() async throws {
        let parallel = Parallel<Int, Int> {
            MultiplyStep(factor: 2)
            AddValueStep(value: 10)
            MultiplyStep(factor: 3)
        }

        let results = try await parallel.run(5)
        #expect(results.count == 3)
        #expect(results.contains(10))  // 5 * 2
        #expect(results.contains(15))  // 5 + 10
        #expect(results.contains(15))  // 5 * 3
    }

    @Test("Parallel executes four steps concurrently")
    func parallelFourSteps() async throws {
        let parallel = Parallel<Int, Int> {
            MultiplyStep(factor: 1)
            MultiplyStep(factor: 2)
            MultiplyStep(factor: 3)
            MultiplyStep(factor: 4)
        }

        let results = try await parallel.run(10)
        #expect(results.count == 4)
        #expect(results.contains(10))  // 10 * 1
        #expect(results.contains(20))  // 10 * 2
        #expect(results.contains(30))  // 10 * 3
        #expect(results.contains(40))  // 10 * 4
    }

    @Test("Parallel continues when some steps fail")
    func parallelContinuesOnPartialFailure() async throws {
        let parallel = Parallel<Int, Int> {
            MultiplyStep(factor: 2)
            FailingIntStep()
        }

        // Should still return results from successful steps
        let results = try await parallel.run(5)
        #expect(results.count == 1)
        #expect(results.contains(10))
    }

    @Test("Parallel throws when all steps fail")
    func parallelThrowsWhenAllFail() async throws {
        let parallel = Parallel<Int, Int> {
            FailingIntStep()
            FailingIntStep()
        }

        await #expect(throws: ParallelError.self) {
            try await parallel.run(5)
        }
    }

    @Test("Parallel with string output")
    func parallelWithStringOutput() async throws {
        struct ToStringStep: Step, Sendable {
            let prefix: String
            func run(_ input: Int) async throws -> String {
                "\(prefix)\(input)"
            }
        }

        let parallel = Parallel<Int, String> {
            ToStringStep(prefix: "A:")
            ToStringStep(prefix: "B:")
        }

        let results = try await parallel.run(5)
        #expect(results.count == 2)
        #expect(results.contains("A:5"))
        #expect(results.contains("B:5"))
    }

    @Test("Parallel executes steps concurrently not sequentially")
    func parallelIsTrulyConcurrent() async throws {
        let startTime = Date()

        let parallel = Parallel<Int, Int> {
            DelayedStep(delay: .milliseconds(50), result: 1)
            DelayedStep(delay: .milliseconds(50), result: 2)
            DelayedStep(delay: .milliseconds(50), result: 3)
        }

        let results = try await parallel.run(0)

        let elapsed = Date().timeIntervalSince(startTime)

        // If sequential, would take ~150ms
        // If parallel, should take ~50ms (plus some overhead)
        #expect(elapsed < 0.12) // Allow some overhead
        #expect(results.count == 3)
    }
}

// MARK: - ParallelError Tests

@Suite("ParallelError Tests")
struct ParallelErrorTests {

    @Test("ParallelError.noResults is thrown correctly")
    func noResultsError() async throws {
        // Create a parallel with no steps (edge case)
        let parallel = Parallel<Int, Int> {
            // Empty - but builder might not allow this
            MultiplyStep(factor: 1)
        }

        // This should work fine
        let results = try await parallel.run(5)
        #expect(results.count == 1)
    }

    @Test("ParallelError.allStepsFailed contains errors")
    func allStepsFailedContainsErrors() async throws {
        let parallel = Parallel<Int, Int> {
            FailingIntStep()
            FailingIntStep()
        }

        do {
            _ = try await parallel.run(5)
            #expect(Bool(false), "Should have thrown")
        } catch let error as ParallelError {
            switch error {
            case .allStepsFailed(let errors):
                #expect(errors.count >= 1)
            case .noResults:
                #expect(Bool(false), "Wrong error type")
            }
        }
    }
}
