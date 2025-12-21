import Testing
import Foundation
@testable import SwiftAgent

// MARK: - Test Helpers

/// A simple step that doubles an integer
struct DoubleStep: Step, Sendable {
    typealias Input = Int
    typealias Output = Int

    func run(_ input: Int) async throws -> Int {
        input * 2
    }
}

/// A step that adds a value
struct AddStep: Step, Sendable {
    let value: Int

    func run(_ input: Int) async throws -> Int {
        input + value
    }
}

/// A step that converts Int to String
struct IntToStringStep: Step, Sendable {
    func run(_ input: Int) async throws -> String {
        String(input)
    }
}

/// A step that throws an error
struct FailingStep: Step, Sendable {
    struct TestError: Error {}

    func run(_ input: Int) async throws -> Int {
        throw TestError()
    }
}

// MARK: - EmptyStep Tests

@Suite("EmptyStep Tests")
struct EmptyStepTests {

    @Test("EmptyStep passes through input unchanged")
    func emptyStepPassthrough() async throws {
        let step = EmptyStep<String>()
        let result = try await step.run("hello")
        #expect(result == "hello")
    }

    @Test("EmptyStep works with various types")
    func emptyStepVariousTypes() async throws {
        let intStep = EmptyStep<Int>()
        let intResult = try await intStep.run(42)
        #expect(intResult == 42)

        let arrayStep = EmptyStep<[Int]>()
        let arrayResult = try await arrayStep.run([1, 2, 3])
        #expect(arrayResult == [1, 2, 3])
    }
}

// MARK: - Transform Tests

@Suite("Transform Tests")
struct TransformTests {

    @Test("Transform applies closure to input")
    func transformAppliesClosure() async throws {
        let transform = Transform<Int, Int> { $0 * 2 }
        let result = try await transform.run(5)
        #expect(result == 10)
    }

    @Test("Transform changes types")
    func transformChangesTypes() async throws {
        let transform = Transform<Int, String> { String($0) }
        let result = try await transform.run(42)
        #expect(result == "42")
    }

    @Test("Transform handles async operations")
    func transformHandlesAsync() async throws {
        let transform = Transform<Int, Int> { value in
            try await Task.sleep(for: .milliseconds(10))
            return value + 1
        }
        let result = try await transform.run(5)
        #expect(result == 6)
    }

    @Test("Transform propagates errors")
    func transformPropagatesErrors() async throws {
        struct CustomError: Error {}
        let transform = Transform<Int, Int> { _ in
            throw CustomError()
        }

        await #expect(throws: CustomError.self) {
            try await transform.run(5)
        }
    }
}

// MARK: - Chain Tests

@Suite("Chain Tests")
struct ChainTests {

    @Test("Chain2 executes steps sequentially")
    func chain2ExecutesSequentially() async throws {
        let chain = Chain2(DoubleStep(), AddStep(value: 1))
        let result = try await chain.run(5)
        // 5 * 2 = 10, 10 + 1 = 11
        #expect(result == 11)
    }

    @Test("Chain3 executes three steps")
    func chain3ExecutesThreeSteps() async throws {
        let chain = Chain3(
            AddStep(value: 1),
            DoubleStep(),
            AddStep(value: 3)
        )
        let result = try await chain.run(5)
        // (5 + 1) = 6, 6 * 2 = 12, 12 + 3 = 15
        #expect(result == 15)
    }

    @Test("Chain with type conversion")
    func chainWithTypeConversion() async throws {
        let chain = Chain2(
            DoubleStep(),
            IntToStringStep()
        )
        let result = try await chain.run(5)
        #expect(result == "10")
    }

    @Test("Chain propagates errors from first step")
    func chainPropagatesFirstStepError() async throws {
        let chain = Chain2(FailingStep(), DoubleStep())

        await #expect(throws: FailingStep.TestError.self) {
            try await chain.run(5)
        }
    }

    @Test("Chain propagates errors from second step")
    func chainPropagatesSecondStepError() async throws {
        let chain = Chain2(DoubleStep(), FailingStep())

        await #expect(throws: FailingStep.TestError.self) {
            try await chain.run(5)
        }
    }
}

// MARK: - StepBuilder Tests

@Suite("StepBuilder Tests")
struct StepBuilderTests {

    @Test("StepBuilder builds single step")
    func stepBuilderSingleStep() async throws {
        @StepBuilder
        func buildStep() -> some Step<Int, Int> {
            DoubleStep()
        }

        let step = buildStep()
        let result = try await step.run(5)
        #expect(result == 10)
    }

    @Test("StepBuilder builds chain of two steps")
    func stepBuilderTwoSteps() async throws {
        @StepBuilder
        func buildStep() -> some Step<Int, Int> {
            DoubleStep()
            AddStep(value: 3)
        }

        let step = buildStep()
        let result = try await step.run(5)
        // 5 * 2 = 10, 10 + 3 = 13
        #expect(result == 13)
    }

    @Test("StepBuilder builds chain of three steps")
    func stepBuilderThreeSteps() async throws {
        @StepBuilder
        func buildStep() -> some Step<Int, Int> {
            AddStep(value: 1)
            DoubleStep()
            AddStep(value: 5)
        }

        let step = buildStep()
        let result = try await step.run(10)
        // (10 + 1) = 11, 11 * 2 = 22, 22 + 5 = 27
        #expect(result == 27)
    }
}

// MARK: - OptionalStep Tests

@Suite("OptionalStep Tests")
struct OptionalStepTests {

    @Test("OptionalStep executes when step is present")
    func optionalStepExecutesWhenPresent() async throws {
        let step = OptionalStep(DoubleStep())
        let result = try await step.run(5)
        #expect(result == 10)
    }

    @Test("OptionalStep throws when step is nil")
    func optionalStepThrowsWhenNil() async throws {
        let step = OptionalStep<DoubleStep>(nil)

        await #expect(throws: OptionalStepError.self) {
            try await step.run(5)
        }
    }
}

// MARK: - ConditionalStep Tests

@Suite("ConditionalStep Tests")
struct ConditionalStepTests {

    @Test("ConditionalStep executes first when condition is true")
    func conditionalStepFirstBranch() async throws {
        let step = ConditionalStep(
            condition: true,
            first: DoubleStep(),
            second: AddStep(value: 100)
        )
        let result = try await step.run(5)
        #expect(result == 10) // DoubleStep: 5 * 2 = 10
    }

    @Test("ConditionalStep executes second when condition is false")
    func conditionalStepSecondBranch() async throws {
        let step = ConditionalStep(
            condition: false,
            first: DoubleStep(),
            second: AddStep(value: 100)
        )
        let result = try await step.run(5)
        #expect(result == 105) // AddStep: 5 + 100 = 105
    }

    @Test("ConditionalStep throws when no step available")
    func conditionalStepThrowsWhenNoStep() async throws {
        let step = ConditionalStep<DoubleStep, DoubleStep>(
            condition: true,
            first: nil,
            second: nil
        )

        await #expect(throws: ConditionalStepError.self) {
            try await step.run(5)
        }
    }
}

// MARK: - ToolError Tests

@Suite("ToolError Tests")
struct ToolErrorTests {

    @Test("ToolError.missingParameters has correct description")
    func missingParametersDescription() {
        let error = ToolError.missingParameters(["param1", "param2"])
        #expect(error.localizedDescription.contains("param1"))
        #expect(error.localizedDescription.contains("param2"))
    }

    @Test("ToolError.invalidParameters has correct description")
    func invalidParametersDescription() {
        let error = ToolError.invalidParameters("Value must be positive")
        #expect(error.localizedDescription.contains("Value must be positive"))
    }

    @Test("ToolError.executionFailed has correct description")
    func executionFailedDescription() {
        let error = ToolError.executionFailed("Timeout occurred")
        #expect(error.localizedDescription.contains("Timeout occurred"))
    }
}
