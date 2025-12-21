import Testing
import Foundation
@testable import SwiftAgent

// MARK: - Test Helpers

/// A step that doubles an integer
struct DoubleIntStep: Step, Sendable {
    func run(_ input: Int) async throws -> Int {
        input * 2
    }
}

/// A step that adds a fixed value
struct AddIntStep: Step, Sendable {
    let value: Int

    func run(_ input: Int) async throws -> Int {
        input + value
    }
}

/// A step that converts to string
struct IntToStrStep: Step, Sendable {
    func run(_ input: Int) async throws -> String {
        String(input)
    }
}

/// A step that fails
struct FailStep: Step, Sendable {
    struct StepError: Error {}

    func run(_ input: Int) async throws -> Int {
        throw StepError()
    }
}

/// A step that counts characters in a string
struct StringLengthStep: Step, Sendable {
    func run(_ input: String) async throws -> Int {
        input.count
    }
}

/// A composite step that doubles then adds 1
struct DoubleAndAddOneStep: Step, Sendable {
    func run(_ input: Int) async throws -> Int {
        input * 2 + 1
    }
}

// MARK: - AnyStep Tests

@Suite("AnyStep Tests")
struct AnyStepTests {

    @Test("AnyStep wraps and executes step")
    func anyStepWrapsAndExecutes() async throws {
        let step = DoubleIntStep()
        let anyStep = AnyStep(step)

        let result = try await anyStep.run(5)
        #expect(result == 10)
    }

    @Test("AnyStep preserves step behavior")
    func anyStepPreservesBehavior() async throws {
        let step = AddIntStep(value: 7)
        let anyStep = AnyStep(step)

        let result = try await anyStep.run(3)
        #expect(result == 10)
    }

    @Test("AnyStep propagates errors")
    func anyStepPropagatesErrors() async throws {
        let step = FailStep()
        let anyStep = AnyStep(step)

        await #expect(throws: FailStep.StepError.self) {
            try await anyStep.run(5)
        }
    }

    @Test("AnyStep allows heterogeneous array")
    func anyStepAllowsHeterogeneousArray() async throws {
        let steps: [AnyStep<Int, Int>] = [
            AnyStep(DoubleIntStep()),
            AnyStep(AddIntStep(value: 3))
        ]

        let results = try await withThrowingTaskGroup(of: Int.self) { group in
            for step in steps {
                group.addTask {
                    try await step.run(5)
                }
            }

            var results: [Int] = []
            for try await result in group {
                results.append(result)
            }
            return results.sorted()
        }

        #expect(results.count == 2)
        #expect(results.contains(10)) // 5 * 2
        #expect(results.contains(8))  // 5 + 3
    }

    @Test("AnyStep works with type-changing steps")
    func anyStepWithTypeChange() async throws {
        let step = IntToStrStep()
        let anyStep = AnyStep(step)

        let result = try await anyStep.run(42)
        #expect(result == "42")
    }
}

// MARK: - eraseToAnyStep Extension Tests

@Suite("eraseToAnyStep Extension Tests")
struct EraseToAnyStepTests {

    @Test("eraseToAnyStep creates AnyStep")
    func eraseToAnyStepCreatesAnyStep() async throws {
        let step = DoubleIntStep()
        let anyStep = step.eraseToAnyStep()

        let result = try await anyStep.run(5)
        #expect(result == 10)
    }

    @Test("eraseToAnyStep preserves type information")
    func eraseToAnyStepPreservesType() async throws {
        let step = AddIntStep(value: 100)
        let anyStep = step.eraseToAnyStep()

        // Type should be AnyStep<Int, Int>
        let typeName = String(describing: type(of: anyStep))
        #expect(typeName.contains("AnyStep"))
    }

    @Test("eraseToAnyStep on string to int step")
    func eraseToAnyStepOnStringStep() async throws {
        let step = StringLengthStep()
        let anyStep = step.eraseToAnyStep()

        let result = try await anyStep.run("hello")
        #expect(result == 5)
    }

    @Test("eraseToAnyStep on composite step")
    func eraseToAnyStepOnCompositeStep() async throws {
        let step = DoubleAndAddOneStep()
        let anyStep = step.eraseToAnyStep()

        let result = try await anyStep.run(5)
        // 5 * 2 + 1 = 11
        #expect(result == 11)
    }
}

// MARK: - AnyStep with Parallel/Race Tests

@Suite("AnyStep with Parallel and Race Tests")
struct AnyStepWithParallelRaceTests {

    @Test("AnyStep works in Parallel")
    func anyStepInParallel() async throws {
        let parallel = Parallel<Int, Int> {
            DoubleIntStep()
            AddIntStep(value: 10)
        }

        let results = try await parallel.run(5)
        #expect(results.count == 2)
        #expect(results.contains(10)) // 5 * 2
        #expect(results.contains(15)) // 5 + 10
    }

    @Test("AnyStep works in Race")
    func anyStepInRace() async throws {
        struct FastStep: Step, Sendable {
            func run(_ input: Int) async throws -> Int { input }
        }
        struct SlowStep: Step, Sendable {
            func run(_ input: Int) async throws -> Int {
                try await Task.sleep(for: .milliseconds(100))
                return input * 100
            }
        }

        let race = Race<Int, Int> {
            FastStep()
            SlowStep()
        }

        let result = try await race.run(5)
        #expect(result == 5) // Fast step wins
    }
}

// MARK: - AnyStep Sendable Tests

@Suite("AnyStep Sendable Tests")
struct AnyStepSendableTests {

    @Test("AnyStep is Sendable")
    func anyStepIsSendable() async throws {
        let anyStep = AnyStep(DoubleIntStep())

        // Can be used across task boundaries
        let result = await Task {
            try? await anyStep.run(5)
        }.value

        #expect(result == 10)
    }

    @Test("AnyStep can be stored in actor")
    func anyStepInActor() async throws {
        actor StepHolder {
            let step: AnyStep<Int, Int>

            init(_ step: AnyStep<Int, Int>) {
                self.step = step
            }

            func execute(_ input: Int) async throws -> Int {
                try await step.run(input)
            }
        }

        let holder = StepHolder(AnyStep(DoubleIntStep()))
        let result = try await holder.execute(5)
        #expect(result == 10)
    }
}
