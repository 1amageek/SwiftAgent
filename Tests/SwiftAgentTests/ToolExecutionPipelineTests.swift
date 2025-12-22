//
//  ToolExecutionPipelineTests.swift
//  SwiftAgent
//
//  Created by SwiftAgent on 2025/01/15.
//

import Testing
import Foundation
@testable import SwiftAgent
import OpenFoundationModels
import OpenFoundationModelsCore

// MARK: - Test Helpers

/// Test output type that conforms to PromptRepresentable
struct TestToolOutput: PromptRepresentable, Sendable {
    let result: String

    var promptRepresentation: Prompt {
        Prompt(result)
    }
}

/// A simple test tool for pipeline testing using GeneratedContent as input
struct SimpleTestTool: Tool {
    typealias Arguments = GeneratedContent
    typealias Output = TestToolOutput

    var name: String { "simple_test_tool" }
    var description: String { "A simple tool for testing" }
    var parameters: GenerationSchema {
        GenerationSchema(
            type: GeneratedContent.self,
            description: "Test input",
            properties: []
        )
    }

    let handler: @Sendable (GeneratedContent) async throws -> TestToolOutput

    init(handler: @escaping @Sendable (GeneratedContent) async throws -> TestToolOutput = { content in
        let value = content.text
        return TestToolOutput(result: "Processed: \(value)")
    }) {
        self.handler = handler
    }

    func call(arguments: GeneratedContent) async throws -> TestToolOutput {
        try await handler(arguments)
    }
}

/// A tool that always fails
struct FailingTestTool: Tool {
    typealias Arguments = GeneratedContent
    typealias Output = TestToolOutput

    var name: String { "failing_tool" }
    var description: String { "A tool that always fails" }
    var parameters: GenerationSchema {
        GenerationSchema(type: GeneratedContent.self, description: "Test input", properties: [])
    }

    struct TestError: Error, Sendable {
        let message: String
    }

    func call(arguments: GeneratedContent) async throws -> TestToolOutput {
        throw TestError(message: "Intentional failure")
    }
}

/// A slow tool for timeout testing
struct SlowTestTool: Tool {
    typealias Arguments = GeneratedContent
    typealias Output = TestToolOutput

    var name: String { "slow_tool" }
    var description: String { "A slow tool for timeout testing" }
    var parameters: GenerationSchema {
        GenerationSchema(type: GeneratedContent.self, description: "Test input", properties: [])
    }

    let delay: Duration

    init(delay: Duration = .seconds(5)) {
        self.delay = delay
    }

    func call(arguments: GeneratedContent) async throws -> TestToolOutput {
        try await Task.sleep(for: delay)
        return TestToolOutput(result: "Slow result: \(arguments.text)")
    }
}

// MARK: - Test Hooks

/// A hook that records all calls for verification (using actor for thread safety)
actor RecordingHookStorage {
    var beforeCalls: [(toolName: String, arguments: String)] = []
    var afterCalls: [(toolName: String, output: String, duration: Duration)] = []
    var errorCalls: [(toolName: String, errorMessage: String)] = []

    func recordBefore(toolName: String, arguments: String) {
        beforeCalls.append((toolName, arguments))
    }

    func recordAfter(toolName: String, output: String, duration: Duration) {
        afterCalls.append((toolName, output, duration))
    }

    func recordError(toolName: String, errorMessage: String) {
        errorCalls.append((toolName, errorMessage))
    }
}

struct RecordingHook: ToolExecutionHook {
    let storage: RecordingHookStorage

    init(storage: RecordingHookStorage = RecordingHookStorage()) {
        self.storage = storage
    }

    func beforeExecution(
        toolName: String,
        arguments: String,
        context: ToolExecutionContext
    ) async throws -> ToolHookDecision {
        await storage.recordBefore(toolName: toolName, arguments: arguments)
        return .proceed
    }

    func afterExecution(
        toolName: String,
        arguments: String,
        output: String,
        duration: Duration,
        context: ToolExecutionContext
    ) async throws {
        await storage.recordAfter(toolName: toolName, output: output, duration: duration)
    }

    func onError(
        toolName: String,
        arguments: String,
        error: Error,
        context: ToolExecutionContext
    ) async throws -> ToolErrorRecovery {
        await storage.recordError(toolName: toolName, errorMessage: "\(error)")
        return .rethrow
    }
}

/// A hook that modifies arguments
struct ArgumentModifyingHook: ToolExecutionHook {
    let modification: @Sendable (String) -> String

    init(modification: @escaping @Sendable (String) -> String) {
        self.modification = modification
    }

    func beforeExecution(
        toolName: String,
        arguments: String,
        context: ToolExecutionContext
    ) async throws -> ToolHookDecision {
        let modified = modification(arguments)
        return .proceedWithModifiedArgs(modified)
    }
}

/// A hook that blocks execution
struct BlockingHook: ToolExecutionHook {
    let blockReason: String

    func beforeExecution(
        toolName: String,
        arguments: String,
        context: ToolExecutionContext
    ) async throws -> ToolHookDecision {
        .block(reason: blockReason)
    }
}

/// A hook that returns fallback on error
struct FallbackHook: ToolExecutionHook {
    let fallbackOutput: String

    func onError(
        toolName: String,
        arguments: String,
        error: Error,
        context: ToolExecutionContext
    ) async throws -> ToolErrorRecovery {
        .fallback(output: fallbackOutput)
    }
}

/// A hook that retries on error
struct RetryHook: ToolExecutionHook {
    let retryDelay: Duration

    func onError(
        toolName: String,
        arguments: String,
        error: Error,
        context: ToolExecutionContext
    ) async throws -> ToolErrorRecovery {
        .retry(after: retryDelay)
    }
}

// MARK: - Test Permission Delegates

/// A permission delegate that allows all (for testing)
struct TestAllowAllDelegate: ToolPermissionDelegate {
    func canUseTool(
        named toolName: String,
        arguments: String,
        context: ToolPermissionContext
    ) async throws -> ToolPermissionResult {
        .allow
    }
}

/// A permission delegate that denies all
struct DenyAllDelegate: ToolPermissionDelegate {
    let reason: String

    func canUseTool(
        named toolName: String,
        arguments: String,
        context: ToolPermissionContext
    ) async throws -> ToolPermissionResult {
        .deny(reason: reason)
    }
}

/// A permission delegate that modifies input
struct InputModifyingDelegate: ToolPermissionDelegate {
    let modification: @Sendable (String) -> String

    func canUseTool(
        named toolName: String,
        arguments: String,
        context: ToolPermissionContext
    ) async throws -> ToolPermissionResult {
        let modified = modification(arguments)
        return .allowWithModifiedInput(modified)
    }
}

// MARK: - Pipeline Tests

@Suite("ToolExecutionPipeline Tests")
struct ToolExecutionPipelineTests {

    @Test("Pipeline executes tool successfully")
    func pipelineExecutesTool() async throws {
        let pipeline = ToolExecutionPipeline()
        let tool = SimpleTestTool()
        let context = ToolExecutionContext(sessionID: "test", turnNumber: 1)

        let input = GeneratedContent(kind: .string("hello"))
        let output = try await pipeline.execute(tool: tool, arguments: input, context: context)

        #expect(output.result == "Processed: hello")
    }

    @Test("Pipeline calls hooks in order")
    func pipelineCallsHooksInOrder() async throws {
        let storage = RecordingHookStorage()
        let hook = RecordingHook(storage: storage)
        let options = ToolPipelineConfiguration(globalHooks: [hook])
        let pipeline = ToolExecutionPipeline(options: options)
        let tool = SimpleTestTool()
        let context = ToolExecutionContext(sessionID: "test", turnNumber: 1)

        let input = GeneratedContent(kind: .string("test"))
        _ = try await pipeline.execute(tool: tool, arguments: input, context: context)

        let beforeCalls = await storage.beforeCalls
        let afterCalls = await storage.afterCalls
        let errorCalls = await storage.errorCalls

        #expect(beforeCalls.count == 1)
        #expect(beforeCalls[0].toolName == "simple_test_tool")
        #expect(afterCalls.count == 1)
        #expect(afterCalls[0].toolName == "simple_test_tool")
        #expect(errorCalls.isEmpty)
    }

    @Test("Pipeline calls onError hook on failure")
    func pipelineCallsOnErrorHook() async throws {
        let storage = RecordingHookStorage()
        let hook = RecordingHook(storage: storage)
        let options = ToolPipelineConfiguration(globalHooks: [hook])
        let pipeline = ToolExecutionPipeline(options: options)
        let tool = FailingTestTool()
        let context = ToolExecutionContext(sessionID: "test", turnNumber: 1)

        let input = GeneratedContent(kind: .string("test"))
        do {
            _ = try await pipeline.execute(tool: tool, arguments: input, context: context)
            Issue.record("Expected error to be thrown")
        } catch {
            let beforeCalls = await storage.beforeCalls
            let errorCalls = await storage.errorCalls
            let afterCalls = await storage.afterCalls

            #expect(beforeCalls.count == 1)
            #expect(errorCalls.count == 1)
            #expect(afterCalls.isEmpty)
        }
    }

    @Test("Pipeline blocks execution with blocking hook")
    func pipelineBlocksWithHook() async throws {
        let hook = BlockingHook(blockReason: "Blocked for testing")
        let options = ToolPipelineConfiguration(globalHooks: [hook])
        let pipeline = ToolExecutionPipeline(options: options)
        let tool = SimpleTestTool()
        let context = ToolExecutionContext(sessionID: "test", turnNumber: 1)

        let input = GeneratedContent(kind: .string("test"))
        do {
            _ = try await pipeline.execute(tool: tool, arguments: input, context: context)
            Issue.record("Expected error to be thrown")
        } catch let error as ToolExecutionError {
            if case .blockedByHook(let name, let reason) = error {
                #expect(name == "simple_test_tool")
                #expect(reason == "Blocked for testing")
            } else {
                Issue.record("Unexpected error type: \(error)")
            }
        }
    }

    @Test("Pipeline denies with permission delegate")
    func pipelineDeniesWithPermission() async throws {
        let delegate = DenyAllDelegate(reason: "Access denied")
        let options = ToolPipelineConfiguration(permissionDelegate: delegate)
        let pipeline = ToolExecutionPipeline(options: options)
        let tool = SimpleTestTool()
        let context = ToolExecutionContext(sessionID: "test", turnNumber: 1)

        let input = GeneratedContent(kind: .string("test"))
        do {
            _ = try await pipeline.execute(tool: tool, arguments: input, context: context)
            Issue.record("Expected error to be thrown")
        } catch let error as ToolExecutionError {
            if case .permissionDenied(let name, let reason) = error {
                #expect(name == "simple_test_tool")
                #expect(reason == "Access denied")
            } else {
                Issue.record("Unexpected error type: \(error)")
            }
        }
    }

    @Test("Pipeline returns fallback on error")
    func pipelineReturnsFallback() async throws {
        let hook = FallbackHook(fallbackOutput: "Fallback result")
        let options = ToolPipelineConfiguration(globalHooks: [hook])
        let pipeline = ToolExecutionPipeline(options: options)
        let tool = FailingTestTool()
        let context = ToolExecutionContext(sessionID: "test", turnNumber: 1)

        let input = GeneratedContent(kind: .string("test"))
        do {
            _ = try await pipeline.execute(tool: tool, arguments: input, context: context)
            Issue.record("Expected fallbackRequested error to be thrown")
        } catch let error as ToolExecutionError {
            if case .fallbackRequested(let output) = error {
                #expect(output == "Fallback result")
            } else {
                Issue.record("Unexpected error type: \(error)")
            }
        }
    }
}

// MARK: - Argument Modification Tests

@Suite("Argument Modification Tests")
struct ArgumentModificationTests {

    @Test("Hook modifies arguments")
    func hookModifiesArguments() async throws {
        actor CapturedValueTracker {
            var value: String?
            func set(_ v: String) { value = v }
        }

        let tracker = CapturedValueTracker()
        let tool = SimpleTestTool { content in
            await tracker.set(content.text)
            return TestToolOutput(result: "Got: \(content.text)")
        }

        let hook = ArgumentModifyingHook { json in
            json.replacingOccurrences(of: "original", with: "modified")
        }
        let options = ToolPipelineConfiguration(globalHooks: [hook])
        let pipeline = ToolExecutionPipeline(options: options)
        let context = ToolExecutionContext(sessionID: "test", turnNumber: 1)

        let input = GeneratedContent(kind: .string("original"))
        _ = try await pipeline.execute(tool: tool, arguments: input, context: context)

        let capturedText = await tracker.value
        #expect(capturedText == "modified")
    }

    @Test("Permission delegate modifies arguments")
    func permissionModifiesArguments() async throws {
        actor CapturedValueTracker {
            var value: String?
            func set(_ v: String) { value = v }
        }

        let tracker = CapturedValueTracker()
        let tool = SimpleTestTool { content in
            await tracker.set(content.text)
            return TestToolOutput(result: "Got: \(content.text)")
        }

        let delegate = InputModifyingDelegate { json in
            json.replacingOccurrences(of: "secret", with: "REDACTED")
        }
        let options = ToolPipelineConfiguration(permissionDelegate: delegate)
        let pipeline = ToolExecutionPipeline(options: options)
        let context = ToolExecutionContext(sessionID: "test", turnNumber: 1)

        let input = GeneratedContent(kind: .string("secret"))
        _ = try await pipeline.execute(tool: tool, arguments: input, context: context)

        let capturedText = await tracker.value
        #expect(capturedText == "REDACTED")
    }

    @Test("Multiple hooks chain argument modifications")
    func multipleHooksChainModifications() async throws {
        actor CapturedValueTracker {
            var value: String?
            func set(_ v: String) { value = v }
        }

        let tracker = CapturedValueTracker()
        let tool = SimpleTestTool { content in
            await tracker.set(content.text)
            return TestToolOutput(result: "Got: \(content.text)")
        }

        let hook1 = ArgumentModifyingHook { json in
            json.replacingOccurrences(of: "a", with: "b")
        }
        let hook2 = ArgumentModifyingHook { json in
            json.replacingOccurrences(of: "b", with: "c")
        }
        let options = ToolPipelineConfiguration(globalHooks: [hook1, hook2])
        let pipeline = ToolExecutionPipeline(options: options)
        let context = ToolExecutionContext(sessionID: "test", turnNumber: 1)

        let input = GeneratedContent(kind: .string("aaa"))
        _ = try await pipeline.execute(tool: tool, arguments: input, context: context)

        // "aaa" -> "bbb" (hook1) -> "ccc" (hook2)
        let capturedText = await tracker.value
        #expect(capturedText == "ccc")
    }
}

// MARK: - Error Tests

@Suite("ToolExecutionError Tests")
struct ToolExecutionErrorTests {

    @Test("permissionDenied error has correct description")
    func permissionDeniedDescription() {
        let error = ToolExecutionError.permissionDenied(toolName: "test", reason: "Not allowed")
        #expect(error.errorDescription?.contains("Permission denied") == true)
        #expect(error.errorDescription?.contains("test") == true)
        #expect(error.errorCodeString == "PERMISSION_DENIED")
    }

    @Test("blockedByHook error has correct description")
    func blockedByHookDescription() {
        let error = ToolExecutionError.blockedByHook(toolName: "test", reason: "Blocked")
        #expect(error.errorDescription?.contains("blocked") == true)
        #expect(error.errorCodeString == "BLOCKED_BY_HOOK")
    }

    @Test("timeout error has correct description")
    func timeoutDescription() {
        let error = ToolExecutionError.timeout(duration: .seconds(30))
        #expect(error.errorDescription?.contains("timed out") == true)
        #expect(error.errorCodeString == "TIMEOUT")
    }

    @Test("fallbackRequested error has correct description")
    func fallbackRequestedDescription() {
        let error = ToolExecutionError.fallbackRequested(output: "fallback")
        #expect(error.errorDescription?.contains("Fallback") == true)
        #expect(error.errorCodeString == "FALLBACK_REQUESTED")
    }

    @Test("argumentParseFailed error has correct description")
    func argumentParseFailedDescription() {
        struct TestError: Error {}
        let error = ToolExecutionError.argumentParseFailed(
            toolName: "test",
            json: "{}",
            underlyingError: TestError()
        )
        #expect(error.errorDescription?.contains("parse") == true)
        #expect(error.errorCodeString == "ARGUMENT_PARSE_FAILED")
    }

    @Test("ToolExecutionError equatable")
    func errorEquatable() {
        let error1 = ToolExecutionError.permissionDenied(toolName: "test", reason: "reason")
        let error2 = ToolExecutionError.permissionDenied(toolName: "test", reason: "reason")
        let error3 = ToolExecutionError.permissionDenied(toolName: "other", reason: "reason")

        #expect(error1 == error2)
        #expect(error1 != error3)
    }
}

// MARK: - Permission Delegate Tests

@Suite("Permission Delegate Tests")
struct PermissionDelegateTests {

    @Test("AllowAllPermissionDelegate allows all")
    func allowAllDelegateAllows() async throws {
        let delegate = AllowAllPermissionDelegate()
        let context = ToolPermissionContext(sessionID: "test", turnNumber: 1)

        let result = try await delegate.canUseTool(
            named: "any_tool",
            arguments: "{}",
            context: context
        )

        if case .allow = result {
            // Success
        } else {
            Issue.record("Expected .allow")
        }
    }

    @Test("BlockListPermissionDelegate blocks specified tools")
    func blockListDelegateBlocks() async throws {
        let delegate = BlockListPermissionDelegate(blockedTools: ["dangerous_tool"])
        let context = ToolPermissionContext(sessionID: "test", turnNumber: 1)

        let allowedResult = try await delegate.canUseTool(
            named: "safe_tool",
            arguments: "{}",
            context: context
        )
        if case .allow = allowedResult {
            // Success
        } else {
            Issue.record("Expected .allow for safe_tool")
        }

        let blockedResult = try await delegate.canUseTool(
            named: "dangerous_tool",
            arguments: "{}",
            context: context
        )
        if case .deny = blockedResult {
            // Success
        } else {
            Issue.record("Expected .deny for dangerous_tool")
        }
    }

    @Test("AllowListPermissionDelegate allows only specified tools")
    func allowListDelegateAllowsOnly() async throws {
        let delegate = AllowListPermissionDelegate(allowedTools: ["safe_tool"])
        let context = ToolPermissionContext(sessionID: "test", turnNumber: 1)

        let allowedResult = try await delegate.canUseTool(
            named: "safe_tool",
            arguments: "{}",
            context: context
        )
        if case .allow = allowedResult {
            // Success
        } else {
            Issue.record("Expected .allow for safe_tool")
        }

        let blockedResult = try await delegate.canUseTool(
            named: "other_tool",
            arguments: "{}",
            context: context
        )
        if case .deny = blockedResult {
            // Success
        } else {
            Issue.record("Expected .deny for other_tool")
        }
    }

    @Test("PermissionLevelDelegate respects levels")
    func permissionLevelDelegateRespectsLevels() async throws {
        let delegate = PermissionLevelDelegate(
            maxLevel: .standard,
            toolLevels: [
                "read_tool": .readOnly,
                "write_tool": .elevated,
                "exec_tool": .dangerous
            ]
        )
        let context = ToolPermissionContext(sessionID: "test", turnNumber: 1)

        // Read tool should be allowed (readOnly <= standard)
        let readResult = try await delegate.canUseTool(
            named: "read_tool",
            arguments: "{}",
            context: context
        )
        if case .allow = readResult {
            // Success
        } else {
            Issue.record("Expected .allow for read_tool")
        }

        // Write tool should be denied (elevated > standard)
        let writeResult = try await delegate.canUseTool(
            named: "write_tool",
            arguments: "{}",
            context: context
        )
        if case .deny = writeResult {
            // Success
        } else {
            Issue.record("Expected .deny for write_tool")
        }

        // Exec tool should be denied (dangerous > standard)
        let execResult = try await delegate.canUseTool(
            named: "exec_tool",
            arguments: "{}",
            context: context
        )
        if case .deny = execResult {
            // Success
        } else {
            Issue.record("Expected .deny for exec_tool")
        }
    }
}

// MARK: - Hook Tests

@Suite("ToolExecutionHook Tests")
struct ToolExecutionHookTests {

    @Test("LoggingToolHook logs execution")
    func loggingHookLogs() async throws {
        actor LogsTracker {
            var logs: [String] = []
            func add(_ message: String) { logs.append(message) }
        }

        let tracker = LogsTracker()
        let hook = LoggingToolHook { message in
            Task { await tracker.add(message) }
        }

        let context = ToolExecutionContext(sessionID: "test", turnNumber: 1, traceID: "trace-123")

        _ = try await hook.beforeExecution(
            toolName: "test_tool",
            arguments: "{}",
            context: context
        )

        try await hook.afterExecution(
            toolName: "test_tool",
            arguments: "{}",
            output: "result",
            duration: .seconds(1),
            context: context
        )

        // Allow async Task to complete
        try await Task.sleep(for: .milliseconds(50))

        let logs = await tracker.logs
        #expect(logs.count == 2)
        #expect(logs[0].contains("Executing"))
        #expect(logs[0].contains("test_tool"))
        #expect(logs[1].contains("Completed"))
    }

    @Test("ToolBlockingHook blocks specified tools")
    func blockingHookBlocksTools() async throws {
        let hook = ToolBlockingHook(blocking: ["blocked_tool"], reason: "Not allowed")
        let context = ToolExecutionContext(sessionID: "test", turnNumber: 1)

        let allowedDecision = try await hook.beforeExecution(
            toolName: "other_tool",
            arguments: "{}",
            context: context
        )
        if case .proceed = allowedDecision {
            // Success
        } else {
            Issue.record("Expected .proceed for other_tool")
        }

        let blockedDecision = try await hook.beforeExecution(
            toolName: "blocked_tool",
            arguments: "{}",
            context: context
        )
        if case .block(let reason) = blockedDecision {
            #expect(reason?.contains("Not allowed") == true)
        } else {
            Issue.record("Expected .block for blocked_tool")
        }
    }

    @Test("Default hook implementations return expected values")
    func defaultHookImplementations() async throws {
        struct MinimalHook: ToolExecutionHook {}

        let hook = MinimalHook()
        let context = ToolExecutionContext(sessionID: "test", turnNumber: 1)

        let beforeDecision = try await hook.beforeExecution(
            toolName: "test",
            arguments: "{}",
            context: context
        )
        if case .proceed = beforeDecision {
            // Success - default implementation returns .proceed
        } else {
            Issue.record("Expected default beforeExecution to return .proceed")
        }

        // afterExecution has no return value, just verify it doesn't throw
        try await hook.afterExecution(
            toolName: "test",
            arguments: "{}",
            output: "result",
            duration: .seconds(1),
            context: context
        )

        struct TestError: Error {}
        let errorRecovery = try await hook.onError(
            toolName: "test",
            arguments: "{}",
            error: TestError(),
            context: context
        )
        if case .rethrow = errorRecovery {
            // Success - default implementation returns .rethrow
        } else {
            Issue.record("Expected default onError to return .rethrow")
        }
    }
}
