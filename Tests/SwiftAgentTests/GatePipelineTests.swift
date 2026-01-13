import Testing
import Foundation
@testable import SwiftAgent

// MARK: - Gate Tests

@Suite("Gate Tests")
struct GateTests {

    @Test("Gate passes through value on .pass")
    func gatePassesThrough() async throws {
        let gate = Gate<String, String> { input in
            .pass(input.uppercased())
        }
        let result = try await gate.run("hello")
        #expect(result == "HELLO")
    }

    @Test("Gate throws on .block")
    func gateBlocks() async throws {
        let gate = Gate<String, String> { _ in
            .block(reason: "Not allowed")
        }

        await #expect(throws: GateError.self) {
            try await gate.run("hello")
        }
    }

    @Test("Gate block error contains reason")
    func gateBlockReason() async throws {
        let gate = Gate<String, String> { _ in
            .block(reason: "Custom reason")
        }

        do {
            _ = try await gate.run("test")
            Issue.record("Expected GateError to be thrown")
        } catch let error as GateError {
            if case .blocked(let reason) = error {
                #expect(reason == "Custom reason")
            } else {
                Issue.record("Unexpected GateError case")
            }
        }
    }

    @Test("Gate can transform types")
    func gateTransformsTypes() async throws {
        let gate = Gate<Int, String> { input in
            .pass("Number: \(input)")
        }
        let result = try await gate.run(42)
        #expect(result == "Number: 42")
    }

    @Test("Gate handles async operations")
    func gateHandlesAsync() async throws {
        let gate = Gate<Int, Int> { input in
            try await Task.sleep(for: .milliseconds(10))
            return .pass(input * 2)
        }
        let result = try await gate.run(5)
        #expect(result == 10)
    }

    @Test("Gate same type convenience initializer")
    func gateSameTypeInitializer() async throws {
        let gate = Gate<String, String>(transform: { input in
            .pass(input.trimmingCharacters(in: .whitespaces))
        })
        let result = try await gate.run("  hello  ")
        #expect(result == "hello")
    }

    @Test("Gate.passthrough passes input unchanged")
    func gatePassthrough() async throws {
        let gate = Gate<String, String>.passthrough()
        let result = try await gate.run("unchanged")
        #expect(result == "unchanged")
    }

    @Test("Gate.block always blocks")
    func gateAlwaysBlocks() async throws {
        let gate = Gate<String, String>.block(reason: "Always blocked")

        await #expect(throws: GateError.self) {
            try await gate.run("anything")
        }
    }

    @Test("Gate can conditionally pass or block")
    func gateConditional() async throws {
        let gate = Gate<Int, Int> { input in
            if input > 0 {
                return .pass(input * 2)
            } else {
                return .block(reason: "Must be positive")
            }
        }

        let positiveResult = try await gate.run(5)
        #expect(positiveResult == 10)

        await #expect(throws: GateError.self) {
            try await gate.run(-1)
        }
    }
}

// MARK: - GateResult Tests

@Suite("GateResult Tests")
struct GateResultTests {

    @Test("GateResult.pass stores value")
    func passStoresValue() {
        let result: GateResult<String> = .pass("test")
        if case .pass(let value) = result {
            #expect(value == "test")
        } else {
            Issue.record("Expected .pass case")
        }
    }

    @Test("GateResult.block stores reason")
    func blockStoresReason() {
        let result: GateResult<String> = .block(reason: "test reason")
        if case .block(let reason) = result {
            #expect(reason == "test reason")
        } else {
            Issue.record("Expected .block case")
        }
    }
}

// MARK: - Pipeline Tests

@Suite("Pipeline Tests")
struct PipelineTests {

    @Test("Pipeline executes single step")
    func pipelineSingleStep() async throws {
        let pipeline = Pipeline {
            Transform<Int, Int> { $0 * 2 }
        }
        let result = try await pipeline.run(5)
        #expect(result == 10)
    }

    @Test("Pipeline chains multiple steps")
    func pipelineChainsSteps() async throws {
        let pipeline = Pipeline {
            Transform<Int, Int> { $0 + 1 }
            Transform<Int, Int> { $0 * 2 }
            Transform<Int, Int> { $0 + 3 }
        }
        let result = try await pipeline.run(5)
        // (5 + 1) = 6, 6 * 2 = 12, 12 + 3 = 15
        #expect(result == 15)
    }

    @Test("Pipeline with type conversion")
    func pipelineTypeConversion() async throws {
        let pipeline = Pipeline {
            Transform<Int, Int> { $0 * 10 }
            Transform<Int, String> { "Value: \($0)" }
        }
        let result = try await pipeline.run(5)
        #expect(result == "Value: 50")
    }

    @Test("Pipeline with Gates")
    func pipelineWithGates() async throws {
        let pipeline = Pipeline {
            Gate<String, String> { input in
                .pass(input.lowercased())
            }
            Transform<String, String> { "[\($0)]" }
            Gate<String, String> { output in
                .pass(output.uppercased())
            }
        }
        let result = try await pipeline.run("HeLLo")
        // "HeLLo" -> "hello" -> "[hello]" -> "[HELLO]"
        #expect(result == "[HELLO]")
    }

    @Test("Pipeline gate can block execution")
    func pipelineGateBlocks() async throws {
        let pipeline = Pipeline {
            Gate<String, String> { input in
                if input.isEmpty {
                    return .block(reason: "Empty input")
                }
                return .pass(input)
            }
            Transform<String, String> { "Processed: \($0)" }
        }

        // Non-empty input works
        let result = try await pipeline.run("hello")
        #expect(result == "Processed: hello")

        // Empty input is blocked
        await #expect(throws: GateError.self) {
            try await pipeline.run("")
        }
    }

    @Test("Pipeline propagates errors")
    func pipelinePropagatesErrors() async throws {
        struct TestError: Error {}

        let pipeline = Pipeline {
            Transform<Int, Int> { _ in throw TestError() }
        }

        await #expect(throws: TestError.self) {
            try await pipeline.run(5)
        }
    }

    @Test("Pipeline with sequential gates")
    func pipelineSequentialGates() async throws {
        let pipeline = Pipeline {
            // Entry gate
            Gate<String, String> { input in
                .pass("entry:\(input)")
            }
            // Processing
            Transform<String, String> { input in
                input.uppercased()
            }
            // Exit gate
            Gate<String, String> { output in
                .pass("exit:\(output)")
            }
        }

        let result = try await pipeline.run("hello")
        // "hello" -> "entry:hello" -> "ENTRY:HELLO" -> "exit:ENTRY:HELLO"
        #expect(result == "exit:ENTRY:HELLO")
    }
}

// MARK: - Pipeline + Declarative Step Integration Tests

@Suite("Pipeline Declarative Step Integration Tests")
struct PipelineDeclarativeStepIntegrationTests {

    struct ProcessingStep: Step, Sendable {
        var body: some Step<String, String> {
            Transform<String, String> { "[\($0)]" }
        }
    }

    @Test("Pipeline can contain declarative Step")
    func pipelineContainsDeclarativeStep() async throws {
        let pipeline = Pipeline {
            Gate<String, String> { .pass($0.lowercased()) }
            ProcessingStep()
            Gate<String, String> { .pass($0.uppercased()) }
        }
        let result = try await pipeline.run("Hello")
        // "Hello" -> "hello" -> "[hello]" -> "[HELLO]"
        #expect(result == "[HELLO]")
    }

    @Test("Step can use Pipeline in body")
    func stepUsesPipeline() async throws {
        struct PipelineStep: Step, Sendable {
            var body: some Step<Int, String> {
                Pipeline {
                    Gate<Int, Int> { input in
                        if input < 0 {
                            return .block(reason: "Negative")
                        }
                        return .pass(input)
                    }
                    Transform<Int, Int> { $0 * 2 }
                    Transform<Int, String> { "Result: \($0)" }
                }
            }
        }

        let step = PipelineStep()

        let result = try await step.run(5)
        #expect(result == "Result: 10")

        await #expect(throws: GateError.self) {
            try await step.run(-1)
        }
    }
}

// MARK: - GateError Tests

@Suite("GateError Tests")
struct GateErrorTests {

    @Test("GateError.blocked has correct description")
    func blockedDescription() {
        let error = GateError.blocked(reason: "Test reason")
        #expect(error.errorDescription?.contains("Test reason") == true)
    }
}
