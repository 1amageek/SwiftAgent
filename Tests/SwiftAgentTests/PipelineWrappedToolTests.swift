//
//  PipelineWrappedToolTests.swift
//  SwiftAgent
//
//  Created by SwiftAgent on 2025/01/15.
//

import Testing
import Foundation
@testable import SwiftAgent
import OpenFoundationModels
import OpenFoundationModelsCore

// MARK: - PipelineWrappedTool Tests

@Suite("PipelineWrappedTool Tests")
struct PipelineWrappedToolTests {

    @Test("Wrapped tool preserves metadata")
    func wrappedToolPreservesMetadata() async throws {
        let pipeline = ToolExecutionPipeline()
        let tool = SimpleTestTool()

        let wrapped = PipelineWrappedAnyTool(
            wrapping: tool,
            pipeline: pipeline,
            contextProvider: { ToolExecutionContext(sessionID: "test", turnNumber: 1) }
        )

        #expect(wrapped.name == "simple_test_tool")
        #expect(wrapped.description == "A simple tool for testing")
    }

    @Test("Wrapped tool executes through pipeline")
    func wrappedToolExecutesThroughPipeline() async throws {
        let storage = RecordingHookStorage()
        let hook = RecordingHook(storage: storage)
        let options = ToolPipelineConfiguration(globalHooks: [hook])
        let pipeline = ToolExecutionPipeline(options: options)
        let tool = SimpleTestTool()

        let wrapped = PipelineWrappedAnyTool(
            wrapping: tool,
            pipeline: pipeline,
            contextProvider: { ToolExecutionContext(sessionID: "test", turnNumber: 1) }
        )

        let input = GeneratedContent(kind: .string("test"))
        let result = try await wrapped.call(arguments: input)

        #expect(result.contains("Processed"))

        let beforeCalls = await storage.beforeCalls
        let afterCalls = await storage.afterCalls
        #expect(beforeCalls.count == 1)
        #expect(afterCalls.count == 1)
    }

    @Test("Wrapped tool calls onToolExecuted callback")
    func wrappedToolCallsCallback() async throws {
        let pipeline = ToolExecutionPipeline()
        let tool = SimpleTestTool()

        actor ExecutedToolsTracker {
            var tools: [String] = []
            func add(_ name: String) { tools.append(name) }
        }

        let tracker = ExecutedToolsTracker()
        let wrapped = PipelineWrappedAnyTool(
            wrapping: tool,
            pipeline: pipeline,
            contextProvider: { ToolExecutionContext(sessionID: "test", turnNumber: 1) },
            onToolExecuted: { toolName in
                await tracker.add(toolName)
            }
        )

        let input = GeneratedContent(kind: .string("test"))
        _ = try await wrapped.call(arguments: input)

        let executedTools = await tracker.tools
        #expect(executedTools == ["simple_test_tool"])
    }

    @Test("Wrapped tool handles fallback")
    func wrappedToolHandlesFallback() async throws {
        let hook = FallbackHook(fallbackOutput: "Fallback result")
        let options = ToolPipelineConfiguration(globalHooks: [hook])
        let pipeline = ToolExecutionPipeline(options: options)
        let tool = FailingTestTool()

        let wrapped = PipelineWrappedAnyTool(
            wrapping: tool,
            pipeline: pipeline,
            contextProvider: { ToolExecutionContext(sessionID: "test", turnNumber: 1) }
        )

        let input = GeneratedContent(kind: .string("test"))
        let result = try await wrapped.call(arguments: input)

        #expect(result == "Fallback result")
    }

    @Test("Array extension wraps all tools")
    func arrayExtensionWrapsAllTools() async throws {
        let pipeline = ToolExecutionPipeline()
        let tools: [any Tool] = [
            SimpleTestTool(),
            FailingTestTool()
        ]

        let wrapped = tools.wrapped(
            with: pipeline,
            contextProvider: { ToolExecutionContext(sessionID: "test", turnNumber: 1) }
        )

        #expect(wrapped.count == 2)
        #expect(wrapped[0].name == "simple_test_tool")
        #expect(wrapped[1].name == "failing_tool")
    }
}

// MARK: - Timeout Tests

@Suite("Tool Timeout Tests")
struct ToolTimeoutTests {

    @Test("Pipeline respects timeout")
    func pipelineRespectsTimeout() async throws {
        let toolOptions = ToolExecutionOptions(timeout: .milliseconds(100))
        let options = ToolPipelineConfiguration(
            toolOptions: ["slow_tool": toolOptions]
        )
        let pipeline = ToolExecutionPipeline(options: options)
        let tool = SlowTestTool(delay: .seconds(5))

        let wrapped = PipelineWrappedAnyTool(
            wrapping: tool,
            pipeline: pipeline,
            contextProvider: { ToolExecutionContext(sessionID: "test", turnNumber: 1) }
        )

        let input = GeneratedContent(kind: .string("test"))
        do {
            _ = try await wrapped.call(arguments: input)
            Issue.record("Expected timeout error")
        } catch let error as ToolExecutionError {
            if case .timeout = error {
                // Success
            } else {
                Issue.record("Expected timeout error, got: \(error)")
            }
        }
    }

    @Test("Pipeline allows completion within timeout")
    func pipelineAllowsCompletionWithinTimeout() async throws {
        let toolOptions = ToolExecutionOptions(timeout: .seconds(5))
        let options = ToolPipelineConfiguration(
            toolOptions: ["slow_tool": toolOptions]
        )
        let pipeline = ToolExecutionPipeline(options: options)
        let tool = SlowTestTool(delay: .milliseconds(50))

        let wrapped = PipelineWrappedAnyTool(
            wrapping: tool,
            pipeline: pipeline,
            contextProvider: { ToolExecutionContext(sessionID: "test", turnNumber: 1) }
        )

        let input = GeneratedContent(kind: .string("test"))
        let result = try await wrapped.call(arguments: input)

        #expect(result.contains("Slow result"))
    }
}

// MARK: - Retry Tests

@Suite("Tool Retry Tests")
struct ToolRetryTests {

    @Test("Pipeline retries on failure")
    func pipelineRetriesOnFailure() async throws {
        actor AttemptTracker {
            var count = 0
            func increment() -> Int {
                count += 1
                return count
            }
        }

        let tracker = AttemptTracker()
        let tool = SimpleTestTool { _ in
            let attemptCount = await tracker.increment()
            if attemptCount < 3 {
                throw FailingTestTool.TestError(message: "Temporary failure")
            }
            return TestToolOutput(result: "Success after \(attemptCount) attempts")
        }

        let retryConfig = RetryConfiguration(
            maxAttempts: 3,
            baseDelay: .milliseconds(10),
            strategy: .fixed
        )
        let toolOptions = ToolExecutionOptions(retry: retryConfig)
        let options = ToolPipelineConfiguration(
            toolOptions: ["simple_test_tool": toolOptions]
        )
        let pipeline = ToolExecutionPipeline(options: options)
        let context = ToolExecutionContext(sessionID: "test", turnNumber: 1)

        let input = GeneratedContent(kind: .string("test"))
        let output = try await pipeline.execute(tool: tool, arguments: input, context: context)

        let attemptCount = await tracker.count
        #expect(attemptCount == 3)
        #expect(output.result == "Success after 3 attempts")
    }

    @Test("Pipeline exhausts retries and throws")
    func pipelineExhaustsRetries() async throws {
        let tool = FailingTestTool()

        let retryConfig = RetryConfiguration(
            maxAttempts: 2,
            baseDelay: .milliseconds(10),
            strategy: .fixed
        )
        let toolOptions = ToolExecutionOptions(retry: retryConfig)
        let options = ToolPipelineConfiguration(
            toolOptions: ["failing_tool": toolOptions]
        )
        let pipeline = ToolExecutionPipeline(options: options)
        let context = ToolExecutionContext(sessionID: "test", turnNumber: 1)

        let input = GeneratedContent(kind: .string("test"))
        do {
            _ = try await pipeline.execute(tool: tool, arguments: input, context: context)
            Issue.record("Expected error after exhausting retries")
        } catch {
            // Expected - retries exhausted
            #expect(error is FailingTestTool.TestError)
        }
    }

    @Test("Exponential backoff increases delay")
    func exponentialBackoffIncreasesDelay() async throws {
        let strategy = RetryStrategy.exponentialBackoff(multiplier: 2.0)

        let delay1 = strategy.delay(for: 1, baseDelay: .milliseconds(100))
        let delay2 = strategy.delay(for: 2, baseDelay: .milliseconds(100))
        let delay3 = strategy.delay(for: 3, baseDelay: .milliseconds(100))

        // delay = baseDelay * multiplier^(attempt-1)
        // Convert to nanoseconds for comparison (since the implementation returns nanoseconds)
        let expectedDelay1 = Duration.nanoseconds(100_000_000)  // 100ms = 100 * 2^0 = 100ms
        let expectedDelay2 = Duration.nanoseconds(200_000_000)  // 100 * 2^1 = 200ms
        let expectedDelay3 = Duration.nanoseconds(400_000_000)  // 100 * 2^2 = 400ms

        #expect(delay1 == expectedDelay1)
        #expect(delay2 == expectedDelay2)
        #expect(delay3 == expectedDelay3)
    }
}

// MARK: - Context Store Tests

@Suite("ToolContextStore Tests")
struct ToolContextStoreTests {

    @Test("Context store tracks tool calls")
    func contextStoreTracksCalls() async throws {
        let store = ToolContextStore(sessionID: "test-session")

        await store.recordToolCall("tool1")
        await store.recordToolCall("tool2")

        let context = await store.createContext()

        #expect(context.sessionID == "test-session")
        #expect(context.previousToolCalls == ["tool1", "tool2"])
    }

    @Test("Context store advances turn")
    func contextStoreAdvancesTurn() async throws {
        let store = ToolContextStore(sessionID: "test-session")

        await store.recordToolCall("tool1")
        let context1 = await store.createContext()
        #expect(context1.turnNumber == 0)

        await store.startNewTurn()
        await store.recordToolCall("tool2")
        let context2 = await store.createContext()

        #expect(context2.turnNumber == 1)
        #expect(context2.previousToolCalls == ["tool2"])
    }

    @Test("Context store creates correct context")
    func contextStoreCreatesContext() async throws {
        let store = ToolContextStore(sessionID: "session-123")

        let context = await store.createContext()

        #expect(context.sessionID == "session-123")
        #expect(context.turnNumber == 0)
        #expect(context.previousToolCalls.isEmpty)
    }
}

// MARK: - Integration Tests

@Suite("Tool Pipeline Integration Tests")
struct ToolPipelineIntegrationTests {

    @Test("Full pipeline with permission, hooks, and execution")
    func fullPipelineIntegration() async throws {
        let storage = RecordingHookStorage()
        let recordingHook = RecordingHook(storage: storage)

        let options = ToolPipelineConfiguration(
            globalHooks: [recordingHook, LoggingToolHook { _ in }],
            permissionDelegate: AllowAllPermissionDelegate()
        )
        let pipeline = ToolExecutionPipeline(options: options)
        let tool = SimpleTestTool()
        let context = ToolExecutionContext(sessionID: "integration-test", turnNumber: 1)

        let input = GeneratedContent(kind: .string("integration"))
        let output = try await pipeline.execute(tool: tool, arguments: input, context: context)

        #expect(output.result == "Processed: integration")

        let beforeCalls = await storage.beforeCalls
        let afterCalls = await storage.afterCalls
        #expect(beforeCalls.count == 1)
        #expect(afterCalls.count == 1)
    }

    @Test("Pipeline with argument modification from both permission and hook")
    func argumentModificationChain() async throws {
        actor CapturedValueTracker {
            var value: String?
            func set(_ v: String) { value = v }
        }

        let tracker = CapturedValueTracker()
        let tool = SimpleTestTool { content in
            await tracker.set(content.text)
            return TestToolOutput(result: "Final: \(content.text)")
        }

        let permissionDelegate = InputModifyingDelegate { json in
            json.replacingOccurrences(of: "step1", with: "step2")
        }
        let hook = ArgumentModifyingHook { json in
            json.replacingOccurrences(of: "step2", with: "step3")
        }

        let options = ToolPipelineConfiguration(
            globalHooks: [hook],
            permissionDelegate: permissionDelegate
        )
        let pipeline = ToolExecutionPipeline(options: options)
        let context = ToolExecutionContext(sessionID: "test", turnNumber: 1)

        let input = GeneratedContent(kind: .string("step1"))
        _ = try await pipeline.execute(tool: tool, arguments: input, context: context)

        // step1 -> step2 (permission) -> step3 (hook)
        let capturedValue = await tracker.value
        #expect(capturedValue == "step3")
    }
}
