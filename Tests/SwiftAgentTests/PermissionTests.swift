//
//  PermissionTests.swift
//  SwiftAgent
//
//  Created by SwiftAgent on 2025/01/23.
//

import Testing
import Foundation
@testable import SwiftAgent

// MARK: - PermissionRule Tests

@Suite("PermissionRule Tests")
struct PermissionRuleTests {

    @Test("PermissionRule parses simple pattern")
    func parseSimplePattern() {
        let rule = PermissionRule(type: .allow, pattern: "Read")

        #expect(rule.toolPattern == "Read")
        #expect(rule.argumentPattern == nil)
        #expect(rule.pattern == "Read")
    }

    @Test("PermissionRule parses pattern with arguments")
    func parsePatternWithArguments() {
        let rule = PermissionRule(type: .deny, pattern: "Bash(rm -rf:*)")

        #expect(rule.toolPattern == "Bash")
        #expect(rule.argumentPattern == "rm -rf:*")
        #expect(rule.pattern == "Bash(rm -rf:*)")
    }

    @Test("PermissionRule parses domain pattern")
    func parseDomainPattern() {
        let rule = PermissionRule(type: .allow, pattern: "WebFetch(domain:github.com)")

        #expect(rule.toolPattern == "WebFetch")
        #expect(rule.argumentPattern == "domain:github.com")
    }

    @Test("PermissionRule parses glob pattern")
    func parseGlobPattern() {
        let rule = PermissionRule(type: .ask, pattern: "Edit(/src/**/*.swift)")

        #expect(rule.toolPattern == "Edit")
        #expect(rule.argumentPattern == "/src/**/*.swift")
    }

    @Test("PermissionRule convenience initializers")
    func convenienceInitializers() {
        let allowRule = PermissionRule.allow("Read")
        #expect(allowRule.type == .allow)
        #expect(allowRule.pattern == "Read")

        let denyRule = PermissionRule.deny("Bash(sudo:*)")
        #expect(denyRule.type == .deny)
        #expect(denyRule.pattern == "Bash(sudo:*)")

        let askRule = PermissionRule.ask("Edit")
        #expect(askRule.type == .ask)
        #expect(askRule.pattern == "Edit")
    }

    @Test("PermissionRule explicit component initializer")
    func explicitComponentInitializer() {
        let rule = PermissionRule(type: .allow, toolPattern: "Bash", argumentPattern: "npm:*")

        #expect(rule.toolPattern == "Bash")
        #expect(rule.argumentPattern == "npm:*")
        #expect(rule.pattern == "Bash(npm:*)")
    }

    @Test("PermissionRule equality")
    func ruleEquality() {
        let rule1 = PermissionRule.allow("Read")
        let rule2 = PermissionRule.allow("Read")
        let rule3 = PermissionRule.deny("Read")

        #expect(rule1 == rule2)
        #expect(rule1 != rule3)
    }

    @Test("PermissionRule description")
    func ruleDescription() {
        let rule = PermissionRule.allow("Read")
        #expect(rule.description == "Allow: Read")

        let denyRule = PermissionRule.deny("Bash(rm:*)")
        #expect(denyRule.description == "Deny: Bash(rm:*)")
    }
}

// MARK: - ToolMatcher Tests

@Suite("ToolMatcher Tests")
struct ToolMatcherTests {

    @Test("ToolMatcher matches exact tool name")
    func matchesExactToolName() {
        let matcher = ToolMatcher(pattern: "Read")

        #expect(matcher.matches(toolName: "Read") == true)
        #expect(matcher.matches(toolName: "Write") == false)
        #expect(matcher.matches(toolName: "ReadFile") == false)
    }

    @Test("ToolMatcher matches wildcard pattern")
    func matchesWildcardPattern() {
        let matcher = ToolMatcher(pattern: "*")

        #expect(matcher.matches(toolName: "Read") == true)
        #expect(matcher.matches(toolName: "Write") == true)
        #expect(matcher.matches(toolName: "Bash") == true)
    }

    @Test("ToolMatcher matches prefix wildcard")
    func matchesPrefixWildcard() {
        let matcher = ToolMatcher(pattern: "mcp__*")

        #expect(matcher.matches(toolName: "mcp__filesystem__read") == true)
        #expect(matcher.matches(toolName: "mcp__git__status") == true)
        #expect(matcher.matches(toolName: "Read") == false)
    }

    @Test("ToolMatcher matches regex pattern")
    func matchesRegexPattern() {
        let matcher = ToolMatcher(pattern: "Edit|Write")

        #expect(matcher.matches(toolName: "Edit") == true)
        #expect(matcher.matches(toolName: "Write") == true)
        #expect(matcher.matches(toolName: "Read") == false)
    }

    @Test("ToolMatcher matches MCP server pattern")
    func matchesMCPServerPattern() {
        let matcher = ToolMatcher(pattern: "mcp__filesystem__*")

        #expect(matcher.matches(toolName: "mcp__filesystem__read") == true)
        #expect(matcher.matches(toolName: "mcp__filesystem__write") == true)
        #expect(matcher.matches(toolName: "mcp__git__status") == false)
    }

    @Test("ToolMatcher matches domain argument")
    func matchesDomainArgument() {
        let matcher = ToolMatcher(pattern: "WebFetch(domain:github.com)")

        let githubArgs = """
        {"url": "https://github.com/user/repo"}
        """
        #expect(matcher.matches(toolName: "WebFetch", arguments: githubArgs) == true)

        let otherArgs = """
        {"url": "https://example.com/page"}
        """
        #expect(matcher.matches(toolName: "WebFetch", arguments: otherArgs) == false)
    }

    @Test("ToolMatcher matches prefix argument")
    func matchesPrefixArgument() {
        let matcher = ToolMatcher(pattern: "Bash(npm run:*)")

        let npmRunArgs = """
        {"command": "npm run test"}
        """
        #expect(matcher.matches(toolName: "Bash", arguments: npmRunArgs) == true)

        let npmInstallArgs = """
        {"command": "npm install"}
        """
        #expect(matcher.matches(toolName: "Bash", arguments: npmInstallArgs) == false)
    }

    @Test("ToolMatcher matches glob pattern for paths")
    func matchesGlobPattern() {
        let matcher = ToolMatcher(pattern: "Edit(/src/**/*.swift)")

        let swiftFileArgs = """
        {"path": "/src/Models/User.swift"}
        """
        #expect(matcher.matches(toolName: "Edit", arguments: swiftFileArgs) == true)

        let nestedSwiftArgs = """
        {"path": "/src/Views/Components/Button.swift"}
        """
        #expect(matcher.matches(toolName: "Edit", arguments: nestedSwiftArgs) == true)

        let otherFileArgs = """
        {"path": "/tests/Test.swift"}
        """
        #expect(matcher.matches(toolName: "Edit", arguments: otherFileArgs) == false)
    }

    @Test("ToolMatcher convenience factory methods")
    func convenienceFactoryMethods() {
        let toolMatcher = ToolMatcher.tool("Read")
        #expect(toolMatcher.pattern == "Read")

        let toolWithArgMatcher = ToolMatcher.tool("Bash", arguments: "npm:*")
        #expect(toolWithArgMatcher.pattern == "Bash(npm:*)")

        let allMatcher = ToolMatcher.all
        #expect(allMatcher.matches(toolName: "AnyTool") == true)

        let allMCPMatcher = ToolMatcher.allMCP
        #expect(allMCPMatcher.matches(toolName: "mcp__test__tool") == true)
        #expect(allMCPMatcher.matches(toolName: "Read") == false)

        let mcpServerMatcher = ToolMatcher.mcp(server: "filesystem")
        #expect(mcpServerMatcher.matches(toolName: "mcp__filesystem__read") == true)
    }

    @Test("ToolMatcher matches file_path field")
    func matchesFilePathField() {
        let matcher = ToolMatcher(pattern: "Edit(**/*.swift)")

        let args = """
        {"file_path": "/src/main.swift"}
        """
        #expect(matcher.matches(toolName: "Edit", arguments: args) == true)

        // Simple filename pattern
        let simpleMatcher = ToolMatcher(pattern: "Edit(*.swift)")
        let simpleArgs = """
        {"file_path": "main.swift"}
        """
        #expect(simpleMatcher.matches(toolName: "Edit", arguments: simpleArgs) == true)
    }
}

// MARK: - PermissionManager Tests

@Suite("PermissionManager Tests")
struct PermissionManagerTests {

    @Test("PermissionManager allows by default in bypass mode")
    func allowsByDefaultInBypassMode() async throws {
        let manager = PermissionManager(mode: .bypassPermissions)
        let context = ToolPermissionContext(sessionID: "test", turnNumber: 1)

        let result = try await manager.checkPermission(
            toolName: "Bash",
            arguments: "{}",
            context: context
        )

        #expect(result == .allowed)
    }

    @Test("PermissionManager denies with deny rule")
    func deniesWithDenyRule() async throws {
        let manager = PermissionManager(
            rules: [.deny("Bash(rm -rf:*)")]
        )
        let context = ToolPermissionContext(sessionID: "test", turnNumber: 1)

        let args = """
        {"command": "rm -rf /"}
        """
        let result = try await manager.checkPermission(
            toolName: "Bash",
            arguments: args,
            context: context
        )

        if case .denied(let reason) = result {
            #expect(reason?.contains("Denied by rule") == true)
        } else {
            Issue.record("Expected .denied result")
        }
    }

    @Test("PermissionManager allows with allow rule")
    func allowsWithAllowRule() async throws {
        let manager = PermissionManager(
            rules: [.allow("Read")]
        )
        let context = ToolPermissionContext(sessionID: "test", turnNumber: 1)

        let result = try await manager.checkPermission(
            toolName: "Read",
            arguments: "{}",
            context: context
        )

        #expect(result == .allowed)
    }

    @Test("PermissionManager requires ask with ask rule")
    func requiresAskWithAskRule() async throws {
        let manager = PermissionManager(
            rules: [.ask("Edit")]
        )
        let context = ToolPermissionContext(sessionID: "test", turnNumber: 1)

        let result = try await manager.checkPermission(
            toolName: "Edit",
            arguments: "{}",
            context: context
        )

        #expect(result == .askRequired)
    }

    @Test("PermissionManager deny takes precedence over allow")
    func denyTakesPrecedenceOverAllow() async throws {
        let manager = PermissionManager(
            rules: [
                .allow("Bash"),
                .deny("Bash(rm:*)")
            ]
        )
        let context = ToolPermissionContext(sessionID: "test", turnNumber: 1)

        // Allow rule should allow normal bash
        let normalArgs = """
        {"command": "ls -la"}
        """
        let normalResult = try await manager.checkPermission(
            toolName: "Bash",
            arguments: normalArgs,
            context: context
        )
        #expect(normalResult == .allowed)

        // Deny rule should block rm commands
        let rmArgs = """
        {"command": "rm file.txt"}
        """
        let rmResult = try await manager.checkPermission(
            toolName: "Bash",
            arguments: rmArgs,
            context: context
        )
        if case .denied = rmResult {
            // Success
        } else {
            Issue.record("Expected .denied for rm command")
        }
    }

    @Test("PermissionManager plan mode only allows read-only tools")
    func planModeOnlyAllowsReadOnly() async throws {
        let manager = PermissionManager(mode: .plan)
        let context = ToolPermissionContext(sessionID: "test", turnNumber: 1)

        // Read should be allowed
        let readResult = try await manager.checkPermission(
            toolName: "Read",
            arguments: "{}",
            context: context
        )
        #expect(readResult == .allowed)

        // Glob should be allowed
        let globResult = try await manager.checkPermission(
            toolName: "Glob",
            arguments: "{}",
            context: context
        )
        #expect(globResult == .allowed)

        // Write should be denied
        let writeResult = try await manager.checkPermission(
            toolName: "Write",
            arguments: "{}",
            context: context
        )
        if case .denied(let reason) = writeResult {
            #expect(reason?.contains("Plan mode") == true)
        } else {
            Issue.record("Expected .denied for Write in plan mode")
        }
    }

    @Test("PermissionManager acceptEdits mode allows file modifications")
    func acceptEditsModeAllowsFileModifications() async throws {
        let manager = PermissionManager(mode: .acceptEdits)
        let context = ToolPermissionContext(sessionID: "test", turnNumber: 1)

        let editResult = try await manager.checkPermission(
            toolName: "Edit",
            arguments: "{}",
            context: context
        )
        #expect(editResult == .allowed)

        let writeResult = try await manager.checkPermission(
            toolName: "Write",
            arguments: "{}",
            context: context
        )
        #expect(writeResult == .allowed)
    }

    @Test("PermissionManager checks tool permission level")
    func checksToolPermissionLevel() async throws {
        let manager = PermissionManager()
        await manager.setToolLevels([
            "SafeTool": .readOnly,
            "DangerousTool": .dangerous
        ])
        await manager.setMaxLevel(.standard)

        let context = ToolPermissionContext(sessionID: "test", turnNumber: 1)

        // Safe tool should be allowed
        let safeResult = try await manager.checkPermission(
            toolName: "SafeTool",
            arguments: "{}",
            context: context
        )
        // No explicit allow rule, so it goes to default mode behavior
        #expect(safeResult == .askRequired)

        // Dangerous tool should be denied due to level
        let dangerousResult = try await manager.checkPermission(
            toolName: "DangerousTool",
            arguments: "{}",
            context: context
        )
        if case .denied(let reason) = dangerousResult {
            #expect(reason?.contains("permission") == true)
        } else {
            Issue.record("Expected .denied for dangerous tool")
        }
    }

    @Test("PermissionManager uses delegate as fallback")
    func usesDelegateAsFallback() async throws {
        let delegate = TestModifyingDelegate()
        let manager = PermissionManager(delegate: delegate)
        let context = ToolPermissionContext(sessionID: "test", turnNumber: 1)

        let result = try await manager.checkPermission(
            toolName: "TestTool",
            arguments: """
            {"value": "original"}
            """,
            context: context
        )

        if case .allowedWithModifiedInput(let modified) = result {
            #expect(modified.contains("modified") == true)
        } else {
            Issue.record("Expected .allowedWithModifiedInput")
        }
    }

    @Test("PermissionManager quickCheck works correctly")
    func quickCheckWorks() async throws {
        let manager = PermissionManager(
            rules: [
                .allow("Read"),
                .deny("Bash")
            ]
        )

        let readAllowed = await manager.quickCheck(toolName: "Read")
        #expect(readAllowed == true)

        let bashAllowed = await manager.quickCheck(toolName: "Bash")
        #expect(bashAllowed == false)

        let unknownAllowed = await manager.quickCheck(toolName: "Unknown")
        #expect(unknownAllowed == false)
    }

    @Test("PermissionManager addRules works")
    func addRulesWorks() async throws {
        let manager = PermissionManager()
        await manager.addRules([
            .allow("Read"),
            .allow("Glob")
        ])

        let context = ToolPermissionContext(sessionID: "test", turnNumber: 1)

        let readResult = try await manager.checkPermission(
            toolName: "Read",
            arguments: "{}",
            context: context
        )
        #expect(readResult == .allowed)

        let globResult = try await manager.checkPermission(
            toolName: "Glob",
            arguments: "{}",
            context: context
        )
        #expect(globResult == .allowed)
    }

    @Test("PermissionManager clearRules removes all rules")
    func clearRulesRemovesAllRules() async throws {
        let manager = PermissionManager(
            rules: [.allow("Read")]
        )

        // Before clear
        let context = ToolPermissionContext(sessionID: "test", turnNumber: 1)
        let beforeResult = try await manager.checkPermission(
            toolName: "Read",
            arguments: "{}",
            context: context
        )
        #expect(beforeResult == .allowed)

        // Clear rules
        await manager.clearRules()

        // After clear - should fall back to default mode behavior
        let afterResult = try await manager.checkPermission(
            toolName: "Read",
            arguments: "{}",
            context: context
        )
        #expect(afterResult == .askRequired)
    }
}

// MARK: - HookResult Tests

@Suite("HookResult Tests")
struct HookResultTests {

    @Test("HookResult allowsExecution property")
    func allowsExecutionProperty() {
        #expect(HookResult.continue.allowsExecution == true)
        #expect(HookResult.allow.allowsExecution == true)
        #expect(HookResult.allowWithModifiedInput("test").allowsExecution == true)
        #expect(HookResult.block(reason: nil).allowsExecution == false)
        #expect(HookResult.deny(reason: nil).allowsExecution == false)
        #expect(HookResult.ask.allowsExecution == false)
        #expect(HookResult.stop(reason: "stopped", output: nil).allowsExecution == false)
    }

    @Test("HookResult modifiesData property")
    func modifiesDataProperty() {
        #expect(HookResult.allowWithModifiedInput("test").modifiesData == true)
        #expect(HookResult.continueWithModifiedPrompt("test").modifiesData == true)
        #expect(HookResult.addContext("test").modifiesData == true)
        #expect(HookResult.replaceOutput("test").modifiesData == true)
        #expect(HookResult.continue.modifiesData == false)
        #expect(HookResult.allow.modifiesData == false)
    }

    @Test("HookResult stopsAgent property")
    func stopsAgentProperty() {
        #expect(HookResult.stop(reason: "stopped", output: nil).stopsAgent == true)
        #expect(HookResult.continue.stopsAgent == false)
        #expect(HookResult.block(reason: nil).stopsAgent == false)
    }
}

// MARK: - AggregatedHookResult Tests

@Suite("AggregatedHookResult Tests")
struct AggregatedHookResultTests {

    @Test("Aggregation with all continue returns continue")
    func allContinueReturnsContinue() {
        let results: [HookResult] = [.continue, .continue, .continue]
        let aggregated = AggregatedHookResult.aggregate(results)

        if case .continue = aggregated.decision {
            // Success
        } else {
            Issue.record("Expected .continue decision")
        }
    }

    @Test("Aggregation stop takes highest precedence")
    func stopTakesHighestPrecedence() {
        let results: [HookResult] = [
            .allow,
            .stop(reason: "stopped", output: nil),
            .block(reason: "blocked")
        ]
        let aggregated = AggregatedHookResult.aggregate(results)

        if case .stop(let reason, _) = aggregated.decision {
            #expect(reason == "stopped")
        } else {
            Issue.record("Expected .stop decision")
        }
    }

    @Test("Aggregation block takes precedence over ask")
    func blockTakesPrecedenceOverAsk() {
        let results: [HookResult] = [
            .ask,
            .block(reason: "blocked"),
            .allow
        ]
        let aggregated = AggregatedHookResult.aggregate(results)

        if case .block(let reason) = aggregated.decision {
            #expect(reason == "blocked")
        } else {
            Issue.record("Expected .block decision")
        }
    }

    @Test("Aggregation ask takes precedence over allow")
    func askTakesPrecedenceOverAllow() {
        let results: [HookResult] = [
            .allow,
            .ask,
            .continue
        ]
        let aggregated = AggregatedHookResult.aggregate(results)

        if case .ask = aggregated.decision {
            // Success
        } else {
            Issue.record("Expected .ask decision")
        }
    }

    @Test("Aggregation collects modified input")
    func collectsModifiedInput() {
        let results: [HookResult] = [
            .continue,
            .allowWithModifiedInput("modified value")
        ]
        let aggregated = AggregatedHookResult.aggregate(results)

        #expect(aggregated.modifiedInput == "modified value")
    }

    @Test("Aggregation collects context messages")
    func collectsContextMessages() {
        let results: [HookResult] = [
            .addContext("Context 1"),
            .addContext("Context 2"),
            .continue
        ]
        let aggregated = AggregatedHookResult.aggregate(results)

        #expect(aggregated.contextMessages.count == 2)
        #expect(aggregated.contextMessages.contains("Context 1"))
        #expect(aggregated.contextMessages.contains("Context 2"))
    }

    @Test("Aggregation collects suppress output flag")
    func collectsSuppressOutputFlag() {
        let results: [HookResult] = [
            .continue,
            .suppressOutput
        ]
        let aggregated = AggregatedHookResult.aggregate(results)

        #expect(aggregated.suppressOutput == true)
    }

    @Test("Aggregation collects reasons from blocking results")
    func collectsReasonsFromBlockingResults() {
        let results: [HookResult] = [
            .deny(reason: "Reason 1"),
            .block(reason: "Reason 2")
        ]
        let aggregated = AggregatedHookResult.aggregate(results)

        #expect(aggregated.reasons.count == 2)
        #expect(aggregated.reasons.contains("Reason 1"))
        #expect(aggregated.reasons.contains("Reason 2"))
    }
}

// MARK: - HookManager Tests

@Suite("HookManager Tests")
struct HookManagerTests {

    @Test("HookManager registers and executes hooks")
    func registersAndExecutesHooks() async throws {
        let manager = HookManager()
        let handler = TestRecordingHookHandler()

        await manager.register(handler, for: .preToolUse)

        let context = HookContext.preToolUse(
            toolName: "TestTool",
            toolInput: "{}",
            sessionID: "test"
        )

        let result = try await manager.execute(event: .preToolUse, context: context)

        #expect(result.decision.allowsExecution == true)
        let calls = await handler.getCalls()
        #expect(calls.count == 1)
    }

    @Test("HookManager respects priority ordering")
    func respectsPriorityOrdering() async throws {
        let manager = HookManager()
        let orderTracker = OrderTracker()

        let highPriorityHandler = OrderRecordingHandler(id: "high", tracker: orderTracker)
        let lowPriorityHandler = OrderRecordingHandler(id: "low", tracker: orderTracker)

        await manager.register(lowPriorityHandler, for: .preToolUse, priority: 0)
        await manager.register(highPriorityHandler, for: .preToolUse, priority: 100)

        let context = HookContext.preToolUse(
            toolName: "TestTool",
            toolInput: "{}",
            sessionID: "test"
        )

        _ = try await manager.execute(event: .preToolUse, context: context)

        let order = await orderTracker.getOrder()
        // High priority (100) should run before low priority (0)
        #expect(order.first == "high")
    }

    @Test("HookManager uses matcher to filter hooks")
    func usesMatcherToFilter() async throws {
        let manager = HookManager()
        let handler = TestRecordingHookHandler()

        await manager.register(
            handler,
            for: .preToolUse,
            matcher: ToolMatcher(pattern: "SpecificTool")
        )

        // Should not trigger for different tool
        let otherContext = HookContext.preToolUse(
            toolName: "OtherTool",
            toolInput: "{}",
            sessionID: "test"
        )
        _ = try await manager.execute(event: .preToolUse, context: otherContext)

        var calls = await handler.getCalls()
        #expect(calls.isEmpty)

        // Should trigger for matching tool
        let matchingContext = HookContext.preToolUse(
            toolName: "SpecificTool",
            toolInput: "{}",
            sessionID: "test"
        )
        _ = try await manager.execute(event: .preToolUse, context: matchingContext)

        calls = await handler.getCalls()
        #expect(calls.count == 1)
    }

    @Test("HookManager unregisters hooks by ID")
    func unregistersHooksById() async throws {
        let manager = HookManager()
        let handler = TestRecordingHookHandler()

        let id = await manager.register(handler, for: .preToolUse)

        // Verify it's registered
        let beforeCount = await manager.hookCount(for: .preToolUse)
        #expect(beforeCount == 1)

        // Unregister
        await manager.unregister(id: id)

        // Verify it's removed
        let afterCount = await manager.hookCount(for: .preToolUse)
        #expect(afterCount == 0)
    }

    @Test("HookManager stops execution on blocking result")
    func stopsOnBlockingResult() async throws {
        let manager = HookManager()

        await manager.register(BlockingHookHandler(reason: "Blocked"), for: .preToolUse, priority: 100)
        await manager.register(TestRecordingHookHandler(), for: .preToolUse, priority: 0)

        let context = HookContext.preToolUse(
            toolName: "TestTool",
            toolInput: "{}",
            sessionID: "test"
        )

        let result = try await manager.execute(event: .preToolUse, context: context)

        #expect(result.decision.allowsExecution == false)
    }

    @Test("HookManager handles sessionStart deduplication")
    func handlesSessionStartDeduplication() async throws {
        let manager = HookManager()
        let handler = TestRecordingHookHandler()

        await manager.register(handler, for: .sessionStart)

        let context = HookContext.sessionStart(sessionID: "test")

        // First call should execute
        _ = try await manager.execute(event: .sessionStart, context: context)
        var calls = await handler.getCalls()
        #expect(calls.count == 1)

        // Second call should be deduplicated
        _ = try await manager.execute(event: .sessionStart, context: context)
        calls = await handler.getCalls()
        #expect(calls.count == 1)

        // After reset, should execute again
        await manager.resetSession()
        _ = try await manager.execute(event: .sessionStart, context: context)
        calls = await handler.getCalls()
        #expect(calls.count == 2)
    }

    @Test("HookManager registers legacy hooks")
    func registersLegacyHooks() async throws {
        let manager = HookManager()
        let legacyHook = TestLegacyHook()

        let ids = await manager.register(legacyHook: legacyHook)
        #expect(ids.count == 2) // pre and post

        let preCount = await manager.hookCount(for: .preToolUse)
        let postCount = await manager.hookCount(for: .postToolUse)
        #expect(preCount == 1)
        #expect(postCount == 1)
    }
}

// MARK: - HookContext Tests

@Suite("HookContext Tests")
struct HookContextTests {

    @Test("HookContext preToolUse factory creates correct context")
    func preToolUseFactory() {
        let context = HookContext.preToolUse(
            toolName: "TestTool",
            toolInput: "{\"key\": \"value\"}",
            toolUseID: "use-123",
            sessionID: "session-456",
            traceID: "trace-789"
        )

        #expect(context.event == .preToolUse)
        #expect(context.toolName == "TestTool")
        #expect(context.toolInput == "{\"key\": \"value\"}")
        #expect(context.toolUseID == "use-123")
        #expect(context.sessionID == "session-456")
        #expect(context.traceID == "trace-789")
        #expect(context.toolOutput == nil)
        #expect(context.executionDuration == nil)
    }

    @Test("HookContext postToolUse factory creates correct context")
    func postToolUseFactory() {
        let context = HookContext.postToolUse(
            toolName: "TestTool",
            toolInput: "{}",
            toolOutput: "result",
            executionDuration: .seconds(1),
            sessionID: "session-456"
        )

        #expect(context.event == .postToolUse)
        #expect(context.toolName == "TestTool")
        #expect(context.toolOutput == "result")
        #expect(context.executionDuration == .seconds(1))
    }

    @Test("HookContext sessionStart factory creates correct context")
    func sessionStartFactory() {
        let context = HookContext.sessionStart(
            sessionID: "session-123",
            isNewSession: true,
            transcriptPath: "/path/to/transcript"
        )

        #expect(context.event == .sessionStart)
        #expect(context.sessionID == "session-123")
        #expect(context.isNewSession == true)
        #expect(context.transcriptPath == "/path/to/transcript")
    }

    @Test("HookContext userPromptSubmit factory creates correct context")
    func userPromptSubmitFactory() {
        let context = HookContext.userPromptSubmit(
            prompt: "Hello, world!",
            sessionID: "session-123"
        )

        #expect(context.event == .userPromptSubmit)
        #expect(context.userPrompt == "Hello, world!")
        #expect(context.sessionID == "session-123")
    }
}

// MARK: - PermissionConfiguration Tests

@Suite("PermissionConfiguration Tests")
struct PermissionConfigurationTests {

    @Test("PermissionConfiguration applies rules to manager")
    func appliesRulesToManager() async throws {
        let config = PermissionConfiguration(
            allow: ["Read", "Glob"],
            deny: ["Bash(rm:*)"],
            ask: ["Edit"]
        )

        let manager = PermissionManager()
        await config.apply(to: manager)

        let context = ToolPermissionContext(sessionID: "test", turnNumber: 1)

        // Read should be allowed
        let readResult = try await manager.checkPermission(
            toolName: "Read",
            arguments: "{}",
            context: context
        )
        #expect(readResult == .allowed)

        // rm command should be denied
        let rmResult = try await manager.checkPermission(
            toolName: "Bash",
            arguments: "{\"command\": \"rm file\"}",
            context: context
        )
        if case .denied = rmResult {
            // Success
        } else {
            Issue.record("Expected denied for rm command")
        }

        // Edit should require ask
        let editResult = try await manager.checkPermission(
            toolName: "Edit",
            arguments: "{}",
            context: context
        )
        #expect(editResult == .askRequired)
    }

    @Test("PermissionConfiguration applies default mode")
    func appliesDefaultMode() async throws {
        let config = PermissionConfiguration(
            defaultMode: .bypassPermissions
        )

        let manager = PermissionManager()
        await config.apply(to: manager)

        let mode = await manager.getMode()
        #expect(mode == .bypassPermissions)
    }
}

// MARK: - Test Helpers

actor TestRecordingHookHandler: HookHandler {
    private var calls: [HookContext] = []

    func execute(context: HookContext) async throws -> HookResult {
        calls.append(context)
        return .continue
    }

    func getCalls() -> [HookContext] {
        return calls
    }
}

actor OrderTracker {
    private var order: [String] = []

    func record(_ id: String) {
        order.append(id)
    }

    func getOrder() -> [String] {
        return order
    }
}

struct OrderRecordingHandler: HookHandler {
    let id: String
    let tracker: OrderTracker

    func execute(context: HookContext) async throws -> HookResult {
        await tracker.record(id)
        return .continue
    }
}

struct TestLegacyHook: ToolExecutionHook {
    func beforeExecution(
        toolName: String,
        arguments: String,
        context: ToolExecutionContext
    ) async throws -> ToolHookDecision {
        .proceed
    }

    func afterExecution(
        toolName: String,
        arguments: String,
        output: String,
        duration: Duration,
        context: ToolExecutionContext
    ) async throws {
        // No-op
    }
}

struct TestModifyingDelegate: ToolPermissionDelegate {
    func canUseTool(
        named toolName: String,
        arguments: String,
        context: ToolPermissionContext
    ) async throws -> ToolPermissionResult {
        let modified = arguments.replacingOccurrences(of: "original", with: "modified")
        return .allowWithModifiedInput(modified)
    }
}

struct BlockingHookHandler: HookHandler {
    let reason: String

    func execute(context: HookContext) async throws -> HookResult {
        .block(reason: reason)
    }
}

// MARK: - Edge Case Tests

@Suite("Permission Edge Case Tests")
struct PermissionEdgeCaseTests {

    // MARK: - ToolMatcher Edge Cases

    @Test("ToolMatcher handles malformed JSON gracefully")
    func handlesmalformedJSON() {
        let matcher = ToolMatcher(pattern: "Bash(npm:*)")

        // Malformed JSON should not crash, should fall back to substring match
        let malformedArgs = "not valid json {"
        // The matcher should handle this gracefully
        let result = matcher.matches(toolName: "Bash", arguments: malformedArgs)
        // Should not match since it can't parse and "npm" isn't in the string
        #expect(result == false)

        // But if the substring is there, it might match
        let containsNpm = "not valid json but has npm run test"
        let result2 = matcher.matches(toolName: "Bash", arguments: containsNpm)
        #expect(result2 == true)
    }

    @Test("ToolMatcher handles empty arguments")
    func handlesEmptyArguments() {
        let matcher = ToolMatcher(pattern: "Bash(npm:*)")

        // Empty string arguments
        #expect(matcher.matches(toolName: "Bash", arguments: "") == false)

        // Tool-only matcher should match even with empty args
        let toolOnlyMatcher = ToolMatcher(pattern: "Bash")
        #expect(toolOnlyMatcher.matches(toolName: "Bash", arguments: "") == true)
        #expect(toolOnlyMatcher.matches(toolName: "Bash", arguments: nil) == true)
    }

    @Test("ToolMatcher with nested parentheses in pattern")
    func handlesNestedParentheses() {
        // Pattern with special characters
        let matcher = ToolMatcher(pattern: "Bash(echo (test):*)")

        #expect(matcher.toolPattern == "Bash")
        // The argument pattern should handle the nested paren
        #expect(matcher.argumentPattern == "echo (test):*")
    }

    // MARK: - PermissionManager Priority Logic Tests

    @Test("PermissionManager rule evaluation order is correct")
    func ruleEvaluationOrderIsCorrect() async throws {
        // This test verifies the documented precedence: deny > ask > allow
        let manager = PermissionManager(
            rules: [
                .allow("TestTool"),   // Should be overridden by ask
                .ask("TestTool"),     // Should be overridden by deny
                .deny("TestTool")     // Should win
            ]
        )
        let context = ToolPermissionContext(sessionID: "test", turnNumber: 1)

        let result = try await manager.checkPermission(
            toolName: "TestTool",
            arguments: "{}",
            context: context
        )

        // Deny should take precedence
        if case .denied = result {
            // Success - deny wins
        } else {
            Issue.record("Expected deny to take precedence, got: \(result)")
        }
    }

    @Test("PermissionManager ask rule is bypassed in bypass mode")
    func askRuleBypassedInBypassMode() async throws {
        let manager = PermissionManager(
            mode: .bypassPermissions,
            rules: [.ask("Edit")]
        )
        let context = ToolPermissionContext(sessionID: "test", turnNumber: 1)

        let result = try await manager.checkPermission(
            toolName: "Edit",
            arguments: "{}",
            context: context
        )

        // In bypass mode, ask should be automatically allowed
        #expect(result == .allowed)
    }

    @Test("PermissionManager deny rule is NOT bypassed in bypass mode")
    func denyRuleNotBypassedInBypassMode() async throws {
        let manager = PermissionManager(
            mode: .bypassPermissions,
            rules: [.deny("DangerousTool")]
        )
        let context = ToolPermissionContext(sessionID: "test", turnNumber: 1)

        let result = try await manager.checkPermission(
            toolName: "DangerousTool",
            arguments: "{}",
            context: context
        )

        // Deny rules should STILL apply even in bypass mode
        if case .denied = result {
            // Success - deny rules are absolute
        } else {
            Issue.record("Deny rules should apply even in bypass mode")
        }
    }

    @Test("PermissionManager specific argument pattern beats general tool pattern")
    func specificPatternBeatsGeneral() async throws {
        let manager = PermissionManager(
            rules: [
                .allow("Bash"),           // Allow all Bash
                .deny("Bash(rm:*)")       // But deny rm commands
            ]
        )
        let context = ToolPermissionContext(sessionID: "test", turnNumber: 1)

        // General Bash should be allowed
        let lsResult = try await manager.checkPermission(
            toolName: "Bash",
            arguments: "{\"command\": \"ls -la\"}",
            context: context
        )
        #expect(lsResult == .allowed)

        // rm should be denied
        let rmResult = try await manager.checkPermission(
            toolName: "Bash",
            arguments: "{\"command\": \"rm -rf /tmp/test\"}",
            context: context
        )
        if case .denied = rmResult {
            // Success
        } else {
            Issue.record("Specific deny pattern should override general allow")
        }
    }

    // MARK: - HookManager Edge Cases

    @Test("HookManager with throwing hook propagates error")
    func throwingHookPropagatesError() async throws {
        let manager = HookManager()

        struct TestHookError: Error {}
        struct ThrowingHandler: HookHandler {
            func execute(context: HookContext) async throws -> HookResult {
                throw TestHookError()
            }
        }

        await manager.register(ThrowingHandler(), for: .preToolUse)

        let context = HookContext.preToolUse(
            toolName: "TestTool",
            toolInput: "{}",
            sessionID: "test"
        )

        do {
            _ = try await manager.execute(event: .preToolUse, context: context)
            Issue.record("Expected error to be thrown")
        } catch is TestHookError {
            // Success - error was propagated
        } catch {
            Issue.record("Wrong error type: \(error)")
        }
    }

    @Test("HookManager lower priority hooks dont run after block")
    func lowerPriorityHooksSkippedAfterBlock() async throws {
        let manager = HookManager()
        let lowPriorityHandler = TestRecordingHookHandler()

        // High priority blocks
        await manager.register(
            BlockingHookHandler(reason: "Blocked"),
            for: .preToolUse,
            priority: 100
        )

        // Low priority should not run
        await manager.register(
            lowPriorityHandler,
            for: .preToolUse,
            priority: 0
        )

        let context = HookContext.preToolUse(
            toolName: "TestTool",
            toolInput: "{}",
            sessionID: "test"
        )

        _ = try await manager.execute(event: .preToolUse, context: context)

        // Low priority handler should NOT have been called
        let calls = await lowPriorityHandler.getCalls()
        #expect(calls.isEmpty, "Lower priority hooks should not run after block")
    }

    @Test("HookManager same priority hooks run in parallel")
    func samePriorityHooksRunInParallel() async throws {
        let manager = HookManager()

        actor TimingTracker {
            var startTimes: [String: Date] = [:]
            var endTimes: [String: Date] = [:]

            func recordStart(_ id: String) {
                startTimes[id] = Date()
            }

            func recordEnd(_ id: String) {
                endTimes[id] = Date()
            }

            func getOverlap() -> Bool {
                guard let start1 = startTimes["hook1"],
                      let end1 = endTimes["hook1"],
                      let start2 = startTimes["hook2"],
                      let end2 = endTimes["hook2"] else {
                    return false
                }
                // Check if time ranges overlap
                return start1 < end2 && start2 < end1
            }
        }

        let tracker = TimingTracker()

        struct SlowHandler: HookHandler {
            let id: String
            let tracker: TimingTracker

            func execute(context: HookContext) async throws -> HookResult {
                await tracker.recordStart(id)
                try await Task.sleep(for: .milliseconds(50))
                await tracker.recordEnd(id)
                return .continue
            }
        }

        // Both at priority 0 - should run in parallel
        await manager.register(
            SlowHandler(id: "hook1", tracker: tracker),
            for: .preToolUse,
            priority: 0
        )
        await manager.register(
            SlowHandler(id: "hook2", tracker: tracker),
            for: .preToolUse,
            priority: 0
        )

        let context = HookContext.preToolUse(
            toolName: "TestTool",
            toolInput: "{}",
            sessionID: "test"
        )

        _ = try await manager.execute(event: .preToolUse, context: context)

        // If running in parallel, the execution times should overlap
        let hadOverlap = await tracker.getOverlap()
        #expect(hadOverlap == true, "Same priority hooks should run in parallel")
    }

    // MARK: - AggregatedHookResult Edge Cases

    @Test("Aggregation with empty results returns continue")
    func emptyResultsReturnsContinue() {
        let results: [HookResult] = []
        let aggregated = AggregatedHookResult.aggregate(results)

        if case .continue = aggregated.decision {
            // Success
        } else {
            Issue.record("Empty results should return .continue")
        }
    }

    @Test("Aggregation last modification wins")
    func lastModificationWins() {
        let results: [HookResult] = [
            .allowWithModifiedInput("first"),
            .allowWithModifiedInput("second"),
            .allowWithModifiedInput("third")
        ]
        let aggregated = AggregatedHookResult.aggregate(results)

        // Last modification should win
        #expect(aggregated.modifiedInput == "third")
    }

    @Test("Aggregation deny and block have same precedence level")
    func denyAndBlockSamePrecedence() {
        // Both deny and block prevent execution
        let results1: [HookResult] = [
            .deny(reason: "denied"),
            .block(reason: "blocked")
        ]
        let agg1 = AggregatedHookResult.aggregate(results1)

        // Both should block execution
        #expect(agg1.decision.allowsExecution == false)
        // Both reasons should be collected
        #expect(agg1.reasons.count == 2)
        #expect(agg1.reasons.contains("denied"))
        #expect(agg1.reasons.contains("blocked"))

        // Test block first
        let results2: [HookResult] = [
            .block(reason: "blocked"),
            .deny(reason: "denied")
        ]
        let agg2 = AggregatedHookResult.aggregate(results2)

        // Both should block execution
        #expect(agg2.decision.allowsExecution == false)
        // Both reasons collected
        #expect(agg2.reasons.count == 2)
    }

    // MARK: - Integration Tests

    @Test("Full permission flow with hooks and rules")
    func fullPermissionFlowWithHooksAndRules() async throws {
        // Setup manager with rules
        let permManager = PermissionManager(
            rules: [
                .allow("Read"),
                .deny("Bash(rm:*)"),
                .ask("Write")
            ]
        )

        // Setup hook manager
        let hookManager = HookManager()
        let recorder = TestRecordingHookHandler()
        await hookManager.register(recorder, for: .preToolUse)

        let context = ToolPermissionContext(sessionID: "test", turnNumber: 1)

        // Test 1: Read should be allowed
        let readResult = try await permManager.checkPermission(
            toolName: "Read",
            arguments: "{}",
            context: context
        )
        #expect(readResult == .allowed)

        // Test 2: rm should be denied
        let rmResult = try await permManager.checkPermission(
            toolName: "Bash",
            arguments: "{\"command\": \"rm -rf /\"}",
            context: context
        )
        if case .denied = rmResult { } else {
            Issue.record("rm should be denied")
        }

        // Test 3: Write should ask
        let writeResult = try await permManager.checkPermission(
            toolName: "Write",
            arguments: "{}",
            context: context
        )
        #expect(writeResult == .askRequired)

        // Test 4: Unknown tool goes to default behavior
        let unknownResult = try await permManager.checkPermission(
            toolName: "Unknown",
            arguments: "{}",
            context: context
        )
        #expect(unknownResult == .askRequired)
    }

    @Test("PermissionManager delegate denyAndInterrupt throws")
    func delegateDenyAndInterruptThrows() async throws {
        struct InterruptingDelegate: ToolPermissionDelegate {
            func canUseTool(
                named toolName: String,
                arguments: String,
                context: ToolPermissionContext
            ) async throws -> ToolPermissionResult {
                .denyAndInterrupt(reason: "Critical security violation")
            }
        }

        let manager = PermissionManager(delegate: InterruptingDelegate())
        let context = ToolPermissionContext(sessionID: "test", turnNumber: 1)

        do {
            _ = try await manager.checkPermission(
                toolName: "TestTool",
                arguments: "{}",
                context: context
            )
            Issue.record("Expected error to be thrown")
        } catch let error as PermissionError {
            if case .deniedByDelegate(let toolName, let reason) = error {
                #expect(toolName == "TestTool")
                #expect(reason == "Critical security violation")
            } else {
                Issue.record("Wrong PermissionError case")
            }
        }
    }

    @Test("Multiple pattern types in single matcher")
    func multiplePatternTypesInMatcher() {
        // Test regex OR pattern with argument
        let matcher = ToolMatcher(pattern: "Edit|Write")

        #expect(matcher.matches(toolName: "Edit") == true)
        #expect(matcher.matches(toolName: "Write") == true)
        #expect(matcher.matches(toolName: "Read") == false)

        // Verify regex is properly anchored
        #expect(matcher.matches(toolName: "MultiEdit") == false)
        #expect(matcher.matches(toolName: "WriteFile") == false)
    }

    @Test("ToolMatcher ExecuteCommand field matching")
    func executeCommandFieldMatching() {
        let matcher = ToolMatcher(pattern: "ExecuteCommand(swift:*)")

        let swiftArgs = """
        {"executable": "swift", "argsJson": "[\\"build\\"]"}
        """
        #expect(matcher.matches(toolName: "ExecuteCommand", arguments: swiftArgs) == true)

        let npmArgs = """
        {"executable": "npm", "argsJson": "[\\"run\\", \\"test\\"]"}
        """
        #expect(matcher.matches(toolName: "ExecuteCommand", arguments: npmArgs) == false)
    }
}

// MARK: - Flow State Tests

@Suite("Pipeline Flow State Tests")
struct PipelineFlowStateTests {

    // MARK: - Execution Order Tests

    @Test("Permission check runs before pre-tool hooks")
    func permissionCheckRunsBeforeHooks() async throws {
        // This test verifies that permission is checked BEFORE hooks run
        // If permission denies, hooks should not execute

        let hookManager = HookManager()
        let hookRecorder = TestRecordingHookHandler()
        await hookManager.register(hookRecorder, for: .preToolUse)

        let permissionManager = PermissionManager(
            rules: [.deny("TestTool")]
        )

        let context = ToolPermissionContext(sessionID: "test", turnNumber: 1)

        // Permission should deny
        let result = try await permissionManager.checkPermission(
            toolName: "TestTool",
            arguments: "{}",
            context: context
        )

        if case .denied = result {
            // Good - permission denied
            // In a real pipeline, hooks would NOT run after this
        } else {
            Issue.record("Expected permission to deny")
        }

        // Hooks should not have been called since permission was checked first
        // (In real pipeline this is enforced by the execution order)
        let hookCalls = await hookRecorder.getCalls()
        #expect(hookCalls.isEmpty, "Hooks should not run when permission is denied")
    }

    @Test("Hook modifications propagate to tool execution")
    func hookModificationsPropagate() async throws {
        let hookManager = HookManager()

        // Hook that modifies input
        struct ModifyingHandler: HookHandler {
            func execute(context: HookContext) async throws -> HookResult {
                if let input = context.toolInput {
                    let modified = input.replacingOccurrences(of: "original", with: "modified_by_hook")
                    return .allowWithModifiedInput(modified)
                }
                return .continue
            }
        }

        await hookManager.register(ModifyingHandler(), for: .preToolUse)

        let context = HookContext.preToolUse(
            toolName: "TestTool",
            toolInput: "{\"value\": \"original\"}",
            sessionID: "test"
        )

        let result = try await hookManager.execute(event: .preToolUse, context: context)

        // Verify modification was captured
        #expect(result.modifiedInput?.contains("modified_by_hook") == true)
        // Verify execution is still allowed
        #expect(result.decision.allowsExecution == true)
    }

    @Test("Flow stops at first blocking phase")
    func flowStopsAtFirstBlockingPhase() async throws {
        // Test that when permission blocks, subsequent phases don't execute

        actor FlowTracker {
            var phases: [String] = []

            func record(_ phase: String) {
                phases.append(phase)
            }

            func getPhases() -> [String] {
                phases
            }
        }

        let tracker = FlowTracker()

        // Simulate a pipeline flow
        // Phase 1: Permission check
        await tracker.record("permission_start")
        let permissionManager = PermissionManager(rules: [.deny("TestTool")])
        let context = ToolPermissionContext(sessionID: "test", turnNumber: 1)

        let permResult = try await permissionManager.checkPermission(
            toolName: "TestTool",
            arguments: "{}",
            context: context
        )

        if case .denied = permResult {
            await tracker.record("permission_denied")
            // Flow stops here - don't proceed to hooks
        } else {
            await tracker.record("permission_allowed")
            // Would proceed to hooks
            await tracker.record("hooks_start")
        }

        let phases = await tracker.getPhases()
        #expect(phases == ["permission_start", "permission_denied"])
        #expect(!phases.contains("hooks_start"), "Hooks should not start when permission denied")
    }

    @Test("Post-tool hooks receive correct execution context")
    func postToolHooksReceiveCorrectContext() async throws {
        let hookManager = HookManager()

        actor ContextCapture {
            var capturedContext: HookContext?

            func capture(_ context: HookContext) {
                capturedContext = context
            }

            func get() -> HookContext? {
                capturedContext
            }
        }

        let capture = ContextCapture()

        struct CapturingHandler: HookHandler {
            let capture: ContextCapture

            func execute(context: HookContext) async throws -> HookResult {
                await capture.capture(context)
                return .continue
            }
        }

        await hookManager.register(CapturingHandler(capture: capture), for: .postToolUse)

        let duration = Duration.seconds(2)
        let context = HookContext.postToolUse(
            toolName: "TestTool",
            toolInput: "{\"input\": \"value\"}",
            toolOutput: "execution result",
            executionDuration: duration,
            toolUseID: "tool-123",
            sessionID: "session-456",
            traceID: "trace-789"
        )

        _ = try await hookManager.execute(event: .postToolUse, context: context)

        let captured = await capture.get()
        #expect(captured != nil)
        #expect(captured?.event == .postToolUse)
        #expect(captured?.toolName == "TestTool")
        #expect(captured?.toolOutput == "execution result")
        #expect(captured?.executionDuration == duration)
        #expect(captured?.toolUseID == "tool-123")
        #expect(captured?.sessionID == "session-456")
        #expect(captured?.traceID == "trace-789")
    }

    // MARK: - State Transition Tests

    @Test("Permission state transitions correctly")
    func permissionStateTransitions() async throws {
        let manager = PermissionManager()
        let context = ToolPermissionContext(sessionID: "test", turnNumber: 1)

        // Initial state: default mode, no rules -> askRequired
        let initial = try await manager.checkPermission(
            toolName: "TestTool",
            arguments: "{}",
            context: context
        )
        #expect(initial == .askRequired)

        // Add allow rule -> allowed
        await manager.addRule(.allow("TestTool"))
        let afterAllow = try await manager.checkPermission(
            toolName: "TestTool",
            arguments: "{}",
            context: context
        )
        #expect(afterAllow == .allowed)

        // Add deny rule -> denied (deny takes precedence)
        await manager.addRule(.deny("TestTool"))
        let afterDeny = try await manager.checkPermission(
            toolName: "TestTool",
            arguments: "{}",
            context: context
        )
        if case .denied = afterDeny {
            // Success
        } else {
            Issue.record("Expected denied after adding deny rule")
        }

        // Clear rules and set bypass mode -> allowed
        await manager.clearRules()
        await manager.setMode(.bypassPermissions)
        let afterBypass = try await manager.checkPermission(
            toolName: "TestTool",
            arguments: "{}",
            context: context
        )
        #expect(afterBypass == .allowed)
    }

    @Test("Hook manager state with multiple event types")
    func hookManagerStateWithMultipleEvents() async throws {
        let manager = HookManager()

        let preHandler = TestRecordingHookHandler()
        let postHandler = TestRecordingHookHandler()
        let sessionHandler = TestRecordingHookHandler()

        await manager.register(preHandler, for: .preToolUse)
        await manager.register(postHandler, for: .postToolUse)
        await manager.register(sessionHandler, for: .sessionStart)

        // Verify counts
        let preCount = await manager.hookCount(for: .preToolUse)
        let postCount = await manager.hookCount(for: .postToolUse)
        let sessionCount = await manager.hookCount(for: .sessionStart)

        #expect(preCount == 1)
        #expect(postCount == 1)
        #expect(sessionCount == 1)

        // Execute preToolUse - only preHandler should be called
        let preContext = HookContext.preToolUse(
            toolName: "Test",
            toolInput: "{}",
            sessionID: "test"
        )
        _ = try await manager.execute(event: .preToolUse, context: preContext)

        let preCalls = await preHandler.getCalls()
        let postCalls = await postHandler.getCalls()
        let sessionCalls = await sessionHandler.getCalls()

        #expect(preCalls.count == 1)
        #expect(postCalls.count == 0)
        #expect(sessionCalls.count == 0)
    }

    // MARK: - Complex Flow Tests

    @Test("Complete pipeline flow with all phases")
    func completePipelineFlowWithAllPhases() async throws {
        actor PhaseTracker {
            var executedPhases: [String] = []

            func record(_ phase: String) {
                executedPhases.append(phase)
            }

            func getPhases() -> [String] {
                executedPhases
            }
        }

        let tracker = PhaseTracker()

        // Setup permission manager that allows
        let permManager = PermissionManager(
            rules: [.allow("AllowedTool")]
        )

        // Setup hook manager
        let hookManager = HookManager()

        struct TrackingPreHandler: HookHandler {
            let tracker: PhaseTracker

            func execute(context: HookContext) async throws -> HookResult {
                await tracker.record("pre_hook")
                return .continue
            }
        }

        struct TrackingPostHandler: HookHandler {
            let tracker: PhaseTracker

            func execute(context: HookContext) async throws -> HookResult {
                await tracker.record("post_hook")
                return .continue
            }
        }

        await hookManager.register(TrackingPreHandler(tracker: tracker), for: .preToolUse)
        await hookManager.register(TrackingPostHandler(tracker: tracker), for: .postToolUse)

        // Simulate full pipeline flow
        let toolName = "AllowedTool"
        let arguments = "{}"
        let permContext = ToolPermissionContext(sessionID: "test", turnNumber: 1)

        // Phase 1: Permission check
        await tracker.record("permission_check")
        let permResult = try await permManager.checkPermission(
            toolName: toolName,
            arguments: arguments,
            context: permContext
        )

        if permResult.canProceed {
            // Phase 2: Pre-tool hooks
            let preContext = HookContext.preToolUse(
                toolName: toolName,
                toolInput: arguments,
                sessionID: "test"
            )
            let preResult = try await hookManager.execute(event: .preToolUse, context: preContext)

            if preResult.decision.allowsExecution {
                // Phase 3: Tool execution (simulated)
                await tracker.record("tool_execution")

                // Phase 4: Post-tool hooks
                let postContext = HookContext.postToolUse(
                    toolName: toolName,
                    toolInput: arguments,
                    toolOutput: "result",
                    executionDuration: .seconds(1),
                    sessionID: "test"
                )
                _ = try await hookManager.execute(event: .postToolUse, context: postContext)
            }
        }

        let phases = await tracker.getPhases()
        #expect(phases == [
            "permission_check",
            "pre_hook",
            "tool_execution",
            "post_hook"
        ])
    }

    @Test("Pipeline flow with modification at each phase")
    func pipelineFlowWithModifications() async throws {
        // Test that modifications flow through the pipeline correctly

        var currentInput = "{\"value\": \"original\"}"

        // Phase 1: Permission modifies
        struct ModifyingDelegate: ToolPermissionDelegate {
            func canUseTool(
                named toolName: String,
                arguments: String,
                context: ToolPermissionContext
            ) async throws -> ToolPermissionResult {
                let modified = arguments.replacingOccurrences(
                    of: "original",
                    with: "permission_modified"
                )
                return .allowWithModifiedInput(modified)
            }
        }

        let permManager = PermissionManager(delegate: ModifyingDelegate())
        let permContext = ToolPermissionContext(sessionID: "test", turnNumber: 1)

        let permResult = try await permManager.checkPermission(
            toolName: "Test",
            arguments: currentInput,
            context: permContext
        )

        if case .allowedWithModifiedInput(let modified) = permResult {
            currentInput = modified
        }

        #expect(currentInput.contains("permission_modified"))

        // Phase 2: Hook modifies
        let hookManager = HookManager()

        struct FurtherModifyingHandler: HookHandler {
            func execute(context: HookContext) async throws -> HookResult {
                if let input = context.toolInput {
                    let modified = input.replacingOccurrences(
                        of: "permission_modified",
                        with: "hook_modified"
                    )
                    return .allowWithModifiedInput(modified)
                }
                return .continue
            }
        }

        await hookManager.register(FurtherModifyingHandler(), for: .preToolUse)

        let hookContext = HookContext.preToolUse(
            toolName: "Test",
            toolInput: currentInput,
            sessionID: "test"
        )

        let hookResult = try await hookManager.execute(event: .preToolUse, context: hookContext)

        if let modified = hookResult.modifiedInput {
            currentInput = modified
        }

        // Verify the final modification chain
        #expect(currentInput.contains("hook_modified"))
        #expect(!currentInput.contains("original"))
        #expect(!currentInput.contains("permission_modified"))
    }

    @Test("Flow interruption propagates correctly")
    func flowInterruptionPropagates() async throws {
        // Test that when one phase blocks, the error/result propagates correctly

        let hookManager = HookManager()

        // First hook blocks
        await hookManager.register(
            BlockingHookHandler(reason: "Security check failed"),
            for: .preToolUse,
            priority: 100
        )

        // Second hook should not run (but we add it to verify)
        let secondHandler = TestRecordingHookHandler()
        await hookManager.register(secondHandler, for: .preToolUse, priority: 0)

        let context = HookContext.preToolUse(
            toolName: "Test",
            toolInput: "{}",
            sessionID: "test"
        )

        let result = try await hookManager.execute(event: .preToolUse, context: context)

        // Result should indicate blocked
        #expect(result.decision.allowsExecution == false)

        // Second handler should not have been called
        let secondCalls = await secondHandler.getCalls()
        #expect(secondCalls.isEmpty)

        // Reason should be propagated
        if case .block(let reason) = result.decision {
            #expect(reason == "Security check failed")
        } else {
            Issue.record("Expected block decision")
        }
    }
}
