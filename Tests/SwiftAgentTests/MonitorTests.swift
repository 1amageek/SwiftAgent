import Testing
import Foundation
@testable import SwiftAgent

// MARK: - Test Helpers

actor TestRecorder {
    var inputs: [Any] = []
    var outputs: [Any] = []
    var errors: [Error] = []
    var durations: [TimeInterval] = []

    func recordInput<T>(_ input: T) {
        inputs.append(input)
    }

    func recordOutput<T>(_ output: T) {
        outputs.append(output)
    }

    func recordError(_ error: Error) {
        errors.append(error)
    }

    func recordDuration(_ duration: TimeInterval) {
        durations.append(duration)
    }
}

/// A simple step for testing
struct SimpleStep: Step, Sendable {
    func run(_ input: Int) async throws -> Int {
        input * 2
    }
}

/// A step that throws an error
struct ErrorStep: Step, Sendable {
    struct TestError: Error {}

    func run(_ input: Int) async throws -> Int {
        throw TestError()
    }
}

/// A step with configurable delay
struct DelayStep: Step, Sendable {
    let delay: Duration

    func run(_ input: Int) async throws -> Int {
        try await Task.sleep(for: delay)
        return input
    }
}

// MARK: - Monitor Tests

@Suite("Monitor Tests")
struct MonitorTests {

    @Test("Monitor executes wrapped step")
    func monitorExecutesWrappedStep() async throws {
        let step = SimpleStep()
        let monitored = Monitor(step: step)

        let result = try await monitored.run(5)
        #expect(result == 10)
    }

    @Test("Monitor calls onInput handler")
    func monitorCallsOnInput() async throws {
        var capturedInput: Int?

        let step = SimpleStep()
        let monitored = step.onInput { input in
            capturedInput = input
        }

        _ = try await monitored.run(5)
        #expect(capturedInput == 5)
    }

    @Test("Monitor calls onOutput handler")
    func monitorCallsOnOutput() async throws {
        var capturedOutput: Int?

        let step = SimpleStep()
        let monitored = step.onOutput { output in
            capturedOutput = output
        }

        _ = try await monitored.run(5)
        #expect(capturedOutput == 10)
    }

    @Test("Monitor calls onError handler on failure")
    func monitorCallsOnError() async throws {
        var capturedError: Error?

        let step = ErrorStep()
        let monitored = step.onError { error in
            capturedError = error
        }

        do {
            _ = try await monitored.run(5)
        } catch {
            // Expected
        }

        #expect(capturedError != nil)
        #expect(capturedError is ErrorStep.TestError)
    }

    @Test("Monitor calls onComplete handler with duration")
    func monitorCallsOnComplete() async throws {
        var capturedDuration: TimeInterval?

        let step = DelayStep(delay: .milliseconds(50))
        let monitored = step.onComplete { duration in
            capturedDuration = duration
        }

        _ = try await monitored.run(5)

        #expect(capturedDuration != nil)
        #expect(capturedDuration! >= 0.04) // At least 40ms
    }

    @Test("Monitor calls onComplete even on error")
    func monitorCallsOnCompleteOnError() async throws {
        var capturedDuration: TimeInterval?

        let step = ErrorStep()
        let monitored = step.onComplete { duration in
            capturedDuration = duration
        }

        do {
            _ = try await monitored.run(5)
        } catch {
            // Expected
        }

        #expect(capturedDuration != nil)
    }
}

// MARK: - Monitor Modifier Tests

@Suite("Monitor Modifier Tests")
struct MonitorModifierTests {

    @Test("onInput modifier creates Monitor")
    func onInputCreatesMonitor() async throws {
        let step = SimpleStep()
        let monitored = step.onInput { _ in }

        #expect(type(of: monitored) == Monitor<SimpleStep>.self)
    }

    @Test("onOutput modifier creates Monitor")
    func onOutputCreatesMonitor() async throws {
        let step = SimpleStep()
        let monitored = step.onOutput { _ in }

        #expect(type(of: monitored) == Monitor<SimpleStep>.self)
    }

    @Test("onError modifier creates Monitor")
    func onErrorCreatesMonitor() async throws {
        let step = SimpleStep()
        let monitored = step.onError { _ in }

        #expect(type(of: monitored) == Monitor<SimpleStep>.self)
    }

    @Test("onComplete modifier creates Monitor")
    func onCompleteCreatesMonitor() async throws {
        let step = SimpleStep()
        let monitored = step.onComplete { _ in }

        #expect(type(of: monitored) == Monitor<SimpleStep>.self)
    }

    @Test("monitor with input and output handlers")
    func monitorWithInputAndOutput() async throws {
        var capturedInput: Int?
        var capturedOutput: Int?

        let step = SimpleStep()
        let monitored = step.monitor(
            input: { capturedInput = $0 },
            output: { capturedOutput = $0 }
        )

        _ = try await monitored.run(5)

        #expect(capturedInput == 5)
        #expect(capturedOutput == 10)
    }

    @Test("monitor with all handlers")
    func monitorWithAllHandlers() async throws {
        var inputCalled = false
        var outputCalled = false
        var completeCalled = false

        let step = SimpleStep()
        let monitored = step.monitor(
            onInput: { _ in inputCalled = true },
            onOutput: { _ in outputCalled = true },
            onError: nil,
            onComplete: { _ in completeCalled = true }
        )

        _ = try await monitored.run(5)

        #expect(inputCalled)
        #expect(outputCalled)
        #expect(completeCalled)
    }
}

// MARK: - Monitor Chaining Tests

@Suite("Monitor Chaining Tests")
struct MonitorChainingTests {

    @Test("Multiple monitors can be chained")
    func multipleMonitorsChained() async throws {
        var inputCount = 0
        var outputCount = 0

        let step = SimpleStep()
        let monitored = step
            .onInput { _ in inputCount += 1 }
            .onOutput { _ in outputCount += 1 }

        _ = try await monitored.run(5)

        // Inner monitor handles input, outer handles output
        #expect(outputCount == 1)
    }
}

// MARK: - Monitor with Different Step Types Tests

@Suite("Monitor with Different Steps Tests")
struct MonitorWithDifferentStepsTests {

    @Test("Monitor works with Transform")
    func monitorWithTransform() async throws {
        var capturedOutput: String?

        let step = Transform<Int, String> { String($0) }
        let monitored = step.onOutput { capturedOutput = $0 }

        let result = try await monitored.run(42)

        #expect(result == "42")
        #expect(capturedOutput == "42")
    }

    @Test("Monitor works with Chain")
    func monitorWithChain() async throws {
        var capturedOutput: Int?

        struct DoubleStep: Step, Sendable {
            func run(_ input: Int) async throws -> Int { input * 2 }
        }
        struct AddStep: Step, Sendable {
            func run(_ input: Int) async throws -> Int { input + 3 }
        }

        let chain = Chain2(DoubleStep(), AddStep())
        let monitored = chain.onOutput { capturedOutput = $0 }

        let result = try await monitored.run(5)

        // 5 * 2 = 10, 10 + 3 = 13
        #expect(result == 13)
        #expect(capturedOutput == 13)
    }
}
