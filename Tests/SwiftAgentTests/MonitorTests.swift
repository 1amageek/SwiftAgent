import Testing
import Foundation
import Synchronization
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
struct SimpleStep: Step {
    func run(_ input: Int) async throws -> Int {
        input * 2
    }
}

/// A step that throws an error
struct ErrorStep: Step {
    struct TestError: Error {}

    func run(_ input: Int) async throws -> Int {
        throw TestError()
    }
}

/// A step with configurable delay
struct DelayStep: Step {
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
        let monitored = step.monitor(onInput: nil, onOutput: nil, onError: nil, onComplete: nil)

        let result = try await monitored.run(5)
        #expect(result == 10)
    }

    @Test("Monitor calls onInput handler")
    func monitorCallsOnInput() async throws {
        let captured = Mutex<Int?>(nil)

        let step = SimpleStep()
        let monitored = step.onInput { input in
            captured.withLock { $0 = input }
        }

        _ = try await monitored.run(5)
        #expect(captured.withLock { $0 } == 5)
    }

    @Test("Monitor calls onOutput handler")
    func monitorCallsOnOutput() async throws {
        let captured = Mutex<Int?>(nil)

        let step = SimpleStep()
        let monitored = step.onOutput { output in
            captured.withLock { $0 = output }
        }

        _ = try await monitored.run(5)
        #expect(captured.withLock { $0 } == 10)
    }

    @Test("Monitor calls onError handler on failure")
    func monitorCallsOnError() async throws {
        let captured = Mutex<Error?>(nil)

        let step = ErrorStep()
        let monitored = step.onError { error in
            captured.withLock { $0 = error }
        }

        do {
            _ = try await monitored.run(5)
        } catch {
            // Expected
        }

        #expect(captured.withLock { $0 } != nil)
        #expect(captured.withLock { $0 } is ErrorStep.TestError)
    }

    @Test("Monitor calls onComplete handler with duration")
    func monitorCallsOnComplete() async throws {
        let captured = Mutex<TimeInterval?>(nil)

        let step = DelayStep(delay: .milliseconds(50))
        let monitored = step.onComplete { duration in
            captured.withLock { $0 = duration }
        }

        _ = try await monitored.run(5)

        let duration = captured.withLock { $0 }
        #expect(duration != nil)
        #expect(duration! >= 0.04) // At least 40ms
    }

    @Test("Monitor calls onComplete even on error")
    func monitorCallsOnCompleteOnError() async throws {
        let captured = Mutex<TimeInterval?>(nil)

        let step = ErrorStep()
        let monitored = step.onComplete { duration in
            captured.withLock { $0 = duration }
        }

        do {
            _ = try await monitored.run(5)
        } catch {
            // Expected
        }

        #expect(captured.withLock { $0 } != nil)
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
        let capturedInput = Mutex<Int?>(nil)
        let capturedOutput = Mutex<Int?>(nil)

        let step = SimpleStep()
        let monitored = step.monitor(
            input: { value in capturedInput.withLock { $0 = value } },
            output: { value in capturedOutput.withLock { $0 = value } }
        )

        _ = try await monitored.run(5)

        #expect(capturedInput.withLock { $0 } == 5)
        #expect(capturedOutput.withLock { $0 } == 10)
    }

    @Test("monitor with all handlers")
    func monitorWithAllHandlers() async throws {
        let inputCalled = Mutex(false)
        let outputCalled = Mutex(false)
        let completeCalled = Mutex(false)

        let step = SimpleStep()
        let monitored = step.monitor(
            onInput: { _ in inputCalled.withLock { $0 = true } },
            onOutput: { _ in outputCalled.withLock { $0 = true } },
            onError: nil,
            onComplete: { _ in completeCalled.withLock { $0 = true } }
        )

        _ = try await monitored.run(5)

        #expect(inputCalled.withLock { $0 })
        #expect(outputCalled.withLock { $0 })
        #expect(completeCalled.withLock { $0 })
    }
}

// MARK: - Monitor Chaining Tests

@Suite("Monitor Chaining Tests")
struct MonitorChainingTests {

    @Test("Multiple monitors can be chained")
    func multipleMonitorsChained() async throws {
        let inputCount = Mutex(0)
        let outputCount = Mutex(0)

        let step = SimpleStep()
        let monitored = step
            .onInput { _ in inputCount.withLock { $0 += 1 } }
            .onOutput { _ in outputCount.withLock { $0 += 1 } }

        _ = try await monitored.run(5)

        // Inner monitor handles input, outer handles output
        #expect(outputCount.withLock { $0 } == 1)
    }
}

// MARK: - Monitor with Different Step Types Tests

@Suite("Monitor with Different Steps Tests")
struct MonitorWithDifferentStepsTests {

    @Test("Monitor works with Transform")
    func monitorWithTransform() async throws {
        let captured = Mutex<String?>(nil)

        let step = Transform<Int, String> { String($0) }
        let monitored = step.onOutput { value in captured.withLock { $0 = value } }

        let result = try await monitored.run(42)

        #expect(result == "42")
        #expect(captured.withLock { $0 } == "42")
    }

    @Test("Monitor works with Chain")
    func monitorWithChain() async throws {
        let captured = Mutex<Int?>(nil)

        struct DoubleStep: Step {
            func run(_ input: Int) async throws -> Int { input * 2 }
        }
        struct AddStep: Step {
            func run(_ input: Int) async throws -> Int { input + 3 }
        }

        let chain = Chain2(DoubleStep(), AddStep())
        let monitored = chain.onOutput { value in captured.withLock { $0 = value } }

        let result = try await monitored.run(5)

        // 5 * 2 = 10, 10 + 3 = 13
        #expect(result == 13)
        #expect(captured.withLock { $0 } == 13)
    }
}
