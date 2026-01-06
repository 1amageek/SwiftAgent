//
//  SecurityTests.swift
//  SwiftAgent
//
//  Created by SwiftAgent on 2025/01/06.
//

import Testing
@testable import SwiftAgent

// MARK: - PM: Pattern Matching Tests

@Suite("PM: Pattern Matching")
struct PatternMatchingTests {

    // MARK: - PM-1: Prefix exact match

    @Test("PM-1: prefix:* matches exact prefix")
    func testPrefixExactMatch() {
        let rule = PermissionRule.bash("git:*")
        let context = ToolContext(toolName: "Bash", arguments: #"{"command": "git"}"#)

        #expect(rule.matches(context), "git:* should match exact 'git'")
    }

    // MARK: - PM-2: Prefix with separators

    @Test("PM-2a: prefix:* matches prefix + space")
    func testPrefixWithSpace() {
        let rule = PermissionRule.bash("git:*")
        let context = ToolContext(toolName: "Bash", arguments: #"{"command": "git status"}"#)

        #expect(rule.matches(context))
    }

    @Test("PM-2b: prefix:* matches prefix + dash")
    func testPrefixWithDash() {
        let rule = PermissionRule.bash("git:*")
        let context = ToolContext(toolName: "Bash", arguments: #"{"command": "git-flow init"}"#)

        #expect(rule.matches(context))
    }

    @Test("PM-2c: prefix:* matches prefix + tab")
    func testPrefixWithTab() {
        let rule = PermissionRule.bash("git:*")
        let context = ToolContext(toolName: "Bash", arguments: #"{"command": "git\tstatus"}"#)

        #expect(rule.matches(context))
    }

    @Test("PM-2d: prefix:* matches prefix + semicolon")
    func testPrefixWithSemicolon() {
        let rule = PermissionRule.bash("git:*")
        let context = ToolContext(toolName: "Bash", arguments: #"{"command": "git;echo done"}"#)

        #expect(rule.matches(context))
    }

    @Test("PM-2e: prefix:* matches prefix + pipe")
    func testPrefixWithPipe() {
        let rule = PermissionRule.bash("git:*")
        let context = ToolContext(toolName: "Bash", arguments: #"{"command": "git|head"}"#)

        #expect(rule.matches(context))
    }

    @Test("PM-2f: prefix:* matches prefix + ampersand")
    func testPrefixWithAmpersand() {
        let rule = PermissionRule.bash("git:*")
        let context = ToolContext(toolName: "Bash", arguments: #"{"command": "git&"}"#)

        #expect(rule.matches(context))
    }

    @Test("PM-2g: prefix:* matches prefix + slash (path)")
    func testPrefixWithSlash() {
        let rule = PermissionRule.bash("git:*")
        let context = ToolContext(toolName: "Bash", arguments: #"{"command": "git/something"}"#)

        #expect(rule.matches(context))
    }

    // MARK: - PM-3: Prefix without separator (should NOT match)

    @Test("PM-3a: prefix:* does NOT match without separator")
    func testPrefixNoSeparator() {
        let rule = PermissionRule.bash("git:*")
        let context = ToolContext(toolName: "Bash", arguments: #"{"command": "gitsomething"}"#)

        #expect(!rule.matches(context), "git:* should NOT match 'gitsomething'")
    }

    @Test("PM-3b: rm:* does NOT match rmdir")
    func testRmNotMatchRmdir() {
        let rule = PermissionRule.bash("rm:*")
        let context = ToolContext(toolName: "Bash", arguments: #"{"command": "rmdir folder"}"#)

        #expect(!rule.matches(context), "rm:* should NOT match 'rmdir'")
    }

    @Test("PM-3c: cat:* does NOT match catch")
    func testCatNotMatchCatch() {
        let rule = PermissionRule.bash("cat:*")
        let context = ToolContext(toolName: "Bash", arguments: #"{"command": "catch error"}"#)

        #expect(!rule.matches(context), "cat:* should NOT match 'catch'")
    }

    // MARK: - PM-4: Path normalization

    @Test("PM-4a: Path normalization resolves ..")
    func testPathNormalizationDoubleDot() {
        let rule = PermissionRule.write("/etc/*")
        let context = ToolContext(
            toolName: "Write",
            arguments: #"{"file_path": "/tmp/../etc/passwd"}"#
        )

        #expect(rule.matches(context), "/tmp/../etc/passwd should normalize to /etc/passwd")
    }

    @Test("PM-4b: Path normalization resolves .")
    func testPathNormalizationSingleDot() {
        let rule = PermissionRule.read("/etc/*")
        let context = ToolContext(
            toolName: "Read",
            arguments: #"{"file_path": "/etc/./passwd"}"#
        )

        #expect(rule.matches(context))
    }

    @Test("PM-4c: Path normalization for Edit")
    func testPathNormalizationEdit() {
        let rule = PermissionRule.edit("/etc/*")
        let context = ToolContext(
            toolName: "Edit",
            arguments: #"{"file_path": "/var/../etc/shadow"}"#
        )

        #expect(rule.matches(context))
    }

    @Test("PM-4d: Deny rule catches path traversal")
    func testDenyWithPathTraversal() {
        let rule = PermissionRule.write("/etc/*")
        let context = ToolContext(
            toolName: "Write",
            arguments: #"{"file_path": "/home/user/../../../etc/passwd"}"#
        )

        #expect(rule.matches(context), "Deny rule should catch path traversal attempts")
    }

    // MARK: - PM-5: Wildcard patterns

    @Test("PM-5a: Wildcard * matches any characters")
    func testWildcardAny() {
        let rule = PermissionRule.write("/tmp/*")
        let context = ToolContext(
            toolName: "Write",
            arguments: #"{"file_path": "/tmp/test.txt"}"#
        )

        #expect(rule.matches(context))
    }

    @Test("PM-5b: Wildcard matches nested paths")
    func testWildcardNestedPath() {
        let rule = PermissionRule.write("/tmp/*")
        let context = ToolContext(
            toolName: "Write",
            arguments: #"{"file_path": "/tmp/subdir/deep/file.txt"}"#
        )

        #expect(rule.matches(context))
    }

    @Test("PM-5c: Tool name wildcard")
    func testToolNameWildcard() {
        let rule = PermissionRule("mcp__github__*")
        let context1 = ToolContext(toolName: "mcp__github__list_repos", arguments: "{}")
        let context2 = ToolContext(toolName: "mcp__github__create_pr", arguments: "{}")
        let context3 = ToolContext(toolName: "mcp__slack__send", arguments: "{}")

        #expect(rule.matches(context1))
        #expect(rule.matches(context2))
        #expect(!rule.matches(context3))
    }
}

// MARK: - EO: Evaluation Order Tests

@Suite("EO: Evaluation Order")
struct EvaluationOrderTests {

    func createMiddleware(
        allow: [PermissionRule] = [],
        deny: [PermissionRule] = [],
        finalDeny: [PermissionRule] = [],
        overrides: [PermissionRule] = [],
        defaultAction: PermissionDecision = .deny
    ) -> PermissionMiddleware {
        let config = PermissionConfiguration(
            allow: allow,
            deny: deny,
            finalDeny: finalDeny,
            overrides: overrides,
            defaultAction: defaultAction,
            handler: nil,
            enableSessionMemory: false
        )
        return PermissionMiddleware(configuration: config)
    }

    // MARK: - EO-1 & EO-2: FinalDeny priority

    @Test("EO-1: FinalDeny checked before session memory")
    func testFinalDenyBeforeSessionMemory() async throws {
        // This test verifies FinalDeny cannot be bypassed
        // Even if we had session memory allowing it, FinalDeny should block
        let middleware = createMiddleware(
            allow: [.bash("sudo:*")],  // Even with allow rule
            finalDeny: [.bash("sudo:*")]
        )

        let context = ToolContext(
            toolName: "Bash",
            arguments: #"{"command": "sudo rm -rf /"}"#
        )

        await #expect(throws: PermissionDenied.self) {
            _ = try await middleware.handle(context) { _ in
                ToolResult.success("executed", duration: .zero)
            }
        }
    }

    @Test("EO-2: FinalDeny blocks even with matching Allow")
    func testFinalDenyBlocksAllow() async throws {
        let middleware = createMiddleware(
            allow: [.tool("Bash")],  // Allow all Bash
            finalDeny: [.bash("rm -rf:*")]  // But absolutely deny rm -rf
        )

        let context = ToolContext(
            toolName: "Bash",
            arguments: #"{"command": "rm -rf /important"}"#
        )

        do {
            _ = try await middleware.handle(context) { _ in
                ToolResult.success("executed", duration: .zero)
            }
            #expect(Bool(false), "Should have thrown PermissionDenied")
        } catch let error as PermissionDenied {
            #expect(error.reason?.contains("final deny") == true)
        }
    }

    // MARK: - EO-3: Override bypasses Deny

    @Test("EO-3: Override bypasses regular Deny")
    func testOverrideBypassesDeny() async throws {
        let middleware = createMiddleware(
            deny: [.bash("rm:*")],  // Deny all rm commands
            overrides: [.bash("rm -f:*")],  // But override allows rm -f
            defaultAction: .allow
        )

        let context = ToolContext(
            toolName: "Bash",
            arguments: #"{"command": "rm -f tempfile"}"#
        )

        let result = try await middleware.handle(context) { _ in
            ToolResult.success("executed", duration: .zero)
        }

        #expect(result.success)
    }

    @Test("EO-3b: Override does not affect non-matching commands")
    func testOverrideSpecific() async throws {
        let middleware = createMiddleware(
            deny: [.bash("rm:*")],
            overrides: [.bash("rm -f:*")],  // Only override rm -f
            defaultAction: .allow
        )

        // rm without -f should still be denied
        let context = ToolContext(
            toolName: "Bash",
            arguments: #"{"command": "rm important_file"}"#
        )

        await #expect(throws: PermissionDenied.self) {
            _ = try await middleware.handle(context) { _ in
                ToolResult.success("executed", duration: .zero)
            }
        }
    }

    // MARK: - EO-4: Override does NOT bypass FinalDeny

    @Test("EO-4: Override does NOT bypass FinalDeny")
    func testOverrideCannotBypassFinalDeny() async throws {
        let middleware = createMiddleware(
            finalDeny: [.bash("rm -rf:*")],  // Absolute deny
            overrides: [.bash("rm -rf:*")]   // Try to override (should fail)
        )

        let context = ToolContext(
            toolName: "Bash",
            arguments: #"{"command": "rm -rf /tmp/test"}"#
        )

        do {
            _ = try await middleware.handle(context) { _ in
                ToolResult.success("executed", duration: .zero)
            }
            #expect(Bool(false), "Should have thrown PermissionDenied")
        } catch let error as PermissionDenied {
            #expect(error.reason?.contains("final deny") == true)
        }
    }

    // MARK: - EO-5 & EO-6: Allow and DefaultAction

    @Test("EO-5: Allow rule takes precedence over DefaultAction")
    func testAllowOverDefaultAction() async throws {
        let middleware = createMiddleware(
            allow: [.tool("Read")],
            defaultAction: .deny
        )

        let context = ToolContext(
            toolName: "Read",
            arguments: #"{"file_path": "/tmp/test.txt"}"#
        )

        let result = try await middleware.handle(context) { _ in
            ToolResult.success("content", duration: .zero)
        }

        #expect(result.success)
    }

    @Test("EO-6: DefaultAction applied when no rules match")
    func testDefaultActionApplied() async throws {
        let middleware = createMiddleware(
            allow: [.tool("Read")],
            defaultAction: .deny
        )

        let context = ToolContext(
            toolName: "Write",  // Not in allow list
            arguments: "{}"
        )

        await #expect(throws: PermissionDenied.self) {
            _ = try await middleware.handle(context) { _ in
                ToolResult.success("written", duration: .zero)
            }
        }
    }

    @Test("EO-6b: DefaultAction allow permits unmatched")
    func testDefaultActionAllowPermits() async throws {
        let middleware = createMiddleware(
            deny: [.bash("sudo:*")],
            defaultAction: .allow
        )

        let context = ToolContext(
            toolName: "Bash",
            arguments: #"{"command": "ls -la"}"#
        )

        let result = try await middleware.handle(context) { _ in
            ToolResult.success("output", duration: .zero)
        }

        #expect(result.success)
    }
}

// MARK: - GI: Guardrail Inheritance Tests

@Suite("GI: Guardrail Inheritance")
struct GuardrailInheritanceTests {

    // MARK: - GI-1: Inner rules prepended

    @Test("GI-1a: Inner allow rules are prepended")
    func testInnerAllowPrepended() {
        let outer = GuardrailConfiguration(allow: [.tool("Read")])
        let inner = GuardrailConfiguration(allow: [.tool("Write")])

        let merged = outer.merged(with: inner)

        #expect(merged.allow.first == .tool("Write"), "Inner rule should be first")
        #expect(merged.allow.count == 2)
    }

    @Test("GI-1b: Inner deny rules are prepended")
    func testInnerDenyPrepended() {
        let outer = GuardrailConfiguration(deny: [.bash("rm:*")])
        let inner = GuardrailConfiguration(deny: [.bash("sudo:*")])

        let merged = outer.merged(with: inner)

        #expect(merged.deny.first == .bash("sudo:*"), "Inner rule should be first")
    }

    @Test("GI-1c: Inner overrides are prepended")
    func testInnerOverridesPrepended() {
        let outer = GuardrailConfiguration(overrides: [.bash("rm:*.log")])
        let inner = GuardrailConfiguration(overrides: [.bash("rm:*.tmp")])

        let merged = outer.merged(with: inner)

        #expect(merged.overrides.first == .bash("rm:*.tmp"))
    }

    // MARK: - GI-2: Inner scalar values override

    @Test("GI-2a: Inner defaultAction overrides outer")
    func testInnerDefaultActionOverrides() {
        let outer = GuardrailConfiguration(defaultAction: .allow)
        let inner = GuardrailConfiguration(defaultAction: .deny)

        let merged = outer.merged(with: inner)

        #expect(merged.defaultAction == .deny)
    }

    @Test("GI-2b: Inner nil defaultAction preserves outer")
    func testInnerNilPreservesOuter() {
        let outer = GuardrailConfiguration(defaultAction: .allow)
        let inner = GuardrailConfiguration(defaultAction: nil)

        let merged = outer.merged(with: inner)

        #expect(merged.defaultAction == .allow)
    }

    // MARK: - GI-3: FinalDeny accumulates

    @Test("GI-3: FinalDeny rules are accumulated")
    func testFinalDenyAccumulates() {
        let outer = GuardrailConfiguration(finalDeny: [.bash("sudo:*")])
        let inner = GuardrailConfiguration(finalDeny: [.bash("rm -rf:*")])

        let merged = outer.merged(with: inner)

        #expect(merged.finalDeny.count == 2)
        #expect(merged.finalDeny.contains(.bash("sudo:*")))
        #expect(merged.finalDeny.contains(.bash("rm -rf:*")))
    }

    // MARK: - GI-4 & GI-5: Override vs FinalDeny inheritance

    @Test("GI-4: Inner Override can relax outer Deny")
    func testInnerOverrideRelaxesOuterDeny() async throws {
        // Outer denies all rm commands, inner overrides rm -i (interactive rm)
        let outer = GuardrailConfiguration(deny: [.bash("rm:*")])
        let inner = GuardrailConfiguration(overrides: [.bash("rm -i:*")])

        let merged = outer.merged(with: inner)

        let permConfig = merged.mergedPermissions(with: PermissionConfiguration(defaultAction: .allow))
        let middleware = PermissionMiddleware(configuration: permConfig)

        // rm -i should be allowed (override bypasses deny)
        let context = ToolContext(
            toolName: "Bash",
            arguments: #"{"command": "rm -i tempfile"}"#
        )

        let result = try await middleware.handle(context) { _ in
            ToolResult.success("executed", duration: .zero)
        }

        #expect(result.success, "rm -i should be allowed by override")
    }

    @Test("GI-5: Inner Override cannot relax outer FinalDeny")
    func testInnerOverrideCannotRelaxFinalDeny() async throws {
        let outer = GuardrailConfiguration(finalDeny: [.bash("rm -rf:*")])
        let inner = GuardrailConfiguration(overrides: [.bash("rm -rf:*")])

        let merged = outer.merged(with: inner)
        let permConfig = merged.mergedPermissions(with: PermissionConfiguration(defaultAction: .allow))
        let middleware = PermissionMiddleware(configuration: permConfig)

        let context = ToolContext(
            toolName: "Bash",
            arguments: #"{"command": "rm -rf /tmp/test"}"#
        )

        await #expect(throws: PermissionDenied.self) {
            _ = try await middleware.handle(context) { _ in
                ToolResult.success("executed", duration: .zero)
            }
        }
    }
}

// MARK: - GuardrailRule Application Tests

@Suite("GuardrailRule Application")
struct GuardrailRuleApplicationTests {

    @Test("Allow rule adds to allow list")
    func testAllowRuleApplication() {
        var config = GuardrailConfiguration()
        Allow(.tool("Read")).apply(to: &config)

        #expect(config.allow.contains(.tool("Read")))
    }

    @Test("Deny rule adds to deny list")
    func testDenyRuleApplication() {
        var config = GuardrailConfiguration()
        Deny(.bash("rm:*")).apply(to: &config)

        #expect(config.deny.contains(.bash("rm:*")))
        #expect(!config.finalDeny.contains(.bash("rm:*")))
    }

    @Test("Deny.final adds to finalDeny list")
    func testDenyFinalApplication() {
        var config = GuardrailConfiguration()
        Deny.final(.bash("sudo:*")).apply(to: &config)

        #expect(config.finalDeny.contains(.bash("sudo:*")))
        #expect(!config.deny.contains(.bash("sudo:*")))
    }

    @Test("Override rule adds to overrides list")
    func testOverrideRuleApplication() {
        var config = GuardrailConfiguration()
        Override(.bash("rm:*.log")).apply(to: &config)

        #expect(config.overrides.contains(.bash("rm:*.log")))
    }
}

// MARK: - PermissionConfiguration Merging Tests

@Suite("PermissionConfiguration Merging")
struct PermissionConfigurationMergingTests {

    @Test("Merged configuration concatenates rules")
    func testMergeConcatenates() {
        let base = PermissionConfiguration(
            allow: [.tool("Read")],
            deny: [.bash("rm:*")]
        )
        let override = PermissionConfiguration(
            allow: [.tool("Write")],
            deny: [.bash("sudo:*")]
        )

        let merged = base.merged(with: override)

        #expect(merged.allow.count == 2)
        #expect(merged.deny.count == 2)
    }

    @Test("Merged configuration deduplicates rules")
    func testMergeDeduplicates() {
        let base = PermissionConfiguration(allow: [.tool("Read"), .tool("Write")])
        let override = PermissionConfiguration(allow: [.tool("Read"), .tool("Grep")])

        let merged = base.merged(with: override)

        #expect(merged.allow.count == 3)  // Read, Write, Grep (no duplicate Read)
    }

    @Test("Override defaultAction takes precedence")
    func testOverrideDefaultAction() {
        let base = PermissionConfiguration(defaultAction: .allow)
        let override = PermissionConfiguration(defaultAction: .deny)

        let merged = base.merged(with: override)

        #expect(merged.defaultAction == .deny)
    }
}

// MARK: - Guardrail Preset Tests

@Suite("Guardrail Presets")
struct GuardrailPresetTests {

    @Test("ReadOnly preset allows read tools")
    func testReadOnlyAllows() {
        let config = Guardrail.readOnly.buildConfiguration()

        #expect(config.allow.contains(.tool("Read")))
        #expect(config.allow.contains(.tool("Glob")))
        #expect(config.allow.contains(.tool("Grep")))
    }

    @Test("ReadOnly preset denies write tools")
    func testReadOnlyDenies() {
        let config = Guardrail.readOnly.buildConfiguration()

        #expect(config.deny.contains(.tool("Write")))
        #expect(config.deny.contains(.tool("Edit")))
        #expect(config.deny.contains(.tool("Bash")))
    }

    @Test("Standard preset allows safe commands")
    func testStandardAllows() {
        let config = Guardrail.standard.buildConfiguration()

        #expect(config.allow.contains(.tool("Read")))
        #expect(config.allow.contains(.bash("git status")))
    }

    @Test("Standard preset denies dangerous commands")
    func testStandardDenies() {
        let config = Guardrail.standard.buildConfiguration()

        // Note: Standard uses regular Deny, not Deny.final
        #expect(config.deny.contains(.bash("rm -rf:*")))
        #expect(config.deny.contains(.bash("sudo:*")))
    }

    @Test("Restrictive preset has sandbox config")
    func testRestrictiveHasSandbox() {
        let config = Guardrail.restrictive.buildConfiguration()

        #expect(config.sandbox != nil)
    }
}

// MARK: - Additional Tests: Edge Cases

@Suite("Edge Cases")
struct EdgeCaseTests {

    // MARK: - Empty and Invalid Input

    @Test("Empty command does not match prefix pattern")
    func testEmptyCommand() {
        let rule = PermissionRule.bash("git:*")
        let context = ToolContext(toolName: "Bash", arguments: #"{"command": ""}"#)

        #expect(!rule.matches(context))
    }

    @Test("Empty file path does not match path pattern")
    func testEmptyFilePath() {
        let rule = PermissionRule.write("/tmp/*")
        let context = ToolContext(toolName: "Write", arguments: #"{"file_path": ""}"#)

        #expect(!rule.matches(context))
    }

    @Test("Invalid JSON returns no match")
    func testInvalidJSON() {
        let rule = PermissionRule.bash("git:*")
        let context = ToolContext(toolName: "Bash", arguments: "not valid json")

        #expect(!rule.matches(context))
    }

    @Test("Missing command field returns no match")
    func testMissingCommandField() {
        let rule = PermissionRule.bash("git:*")
        let context = ToolContext(toolName: "Bash", arguments: #"{"other_field": "value"}"#)

        #expect(!rule.matches(context))
    }

    @Test("Missing file_path field returns no match")
    func testMissingFilePathField() {
        let rule = PermissionRule.write("/tmp/*")
        let context = ToolContext(toolName: "Write", arguments: #"{"content": "data"}"#)

        #expect(!rule.matches(context))
    }

    // MARK: - Case Sensitivity

    @Test("Tool name matching is case-sensitive")
    func testToolNameCaseSensitive() {
        let rule = PermissionRule.tool("Read")
        let context1 = ToolContext(toolName: "Read", arguments: "{}")
        let context2 = ToolContext(toolName: "read", arguments: "{}")
        let context3 = ToolContext(toolName: "READ", arguments: "{}")

        #expect(rule.matches(context1))
        #expect(!rule.matches(context2), "Should NOT match lowercase 'read'")
        #expect(!rule.matches(context3), "Should NOT match uppercase 'READ'")
    }

    @Test("Command pattern matching is case-sensitive")
    func testCommandCaseSensitive() {
        let rule = PermissionRule.bash("git:*")
        let context1 = ToolContext(toolName: "Bash", arguments: #"{"command": "git status"}"#)
        let context2 = ToolContext(toolName: "Bash", arguments: #"{"command": "GIT status"}"#)
        let context3 = ToolContext(toolName: "Bash", arguments: #"{"command": "Git status"}"#)

        #expect(rule.matches(context1))
        #expect(!rule.matches(context2), "Should NOT match uppercase 'GIT'")
        #expect(!rule.matches(context3), "Should NOT match mixed case 'Git'")
    }

    @Test("File path pattern matching is case-sensitive")
    func testFilePathCaseSensitive() {
        let rule = PermissionRule.write("/tmp/*")
        let context1 = ToolContext(toolName: "Write", arguments: #"{"file_path": "/tmp/file.txt"}"#)
        let context2 = ToolContext(toolName: "Write", arguments: #"{"file_path": "/TMP/file.txt"}"#)
        let context3 = ToolContext(toolName: "Write", arguments: #"{"file_path": "/Tmp/file.txt"}"#)

        #expect(rule.matches(context1))
        #expect(!rule.matches(context2), "Should NOT match uppercase '/TMP'")
        #expect(!rule.matches(context3), "Should NOT match mixed case '/Tmp'")
    }

    // MARK: - Multiple Separators and Complex Commands

    @Test("Prefix pattern with command chaining (semicolon)")
    func testPrefixWithCommandChain() {
        let rule = PermissionRule.bash("git:*")
        // Command injection attempt: git; rm -rf /
        let context = ToolContext(
            toolName: "Bash",
            arguments: #"{"command": "git; rm -rf /"}"#
        )

        #expect(rule.matches(context), "Should match because starts with 'git;'")
    }

    @Test("Prefix pattern with subshell")
    func testPrefixWithSubshell() {
        let rule = PermissionRule.bash("echo:*")
        let context = ToolContext(
            toolName: "Bash",
            arguments: #"{"command": "echo $(cat /etc/passwd)"}"#
        )

        #expect(rule.matches(context))
    }

    // MARK: - Unicode and Special Characters

    @Test("Path with unicode characters")
    func testUnicodeInPath() {
        let rule = PermissionRule.write("/tmp/*")
        let context = ToolContext(
            toolName: "Write",
            arguments: #"{"file_path": "/tmp/日本語ファイル.txt"}"#
        )

        #expect(rule.matches(context))
    }

    @Test("Command with unicode characters")
    func testUnicodeInCommand() {
        let rule = PermissionRule.bash("echo:*")
        let context = ToolContext(
            toolName: "Bash",
            arguments: #"{"command": "echo こんにちは"}"#
        )

        #expect(rule.matches(context))
    }

    @Test("Path with spaces")
    func testPathWithSpaces() {
        let rule = PermissionRule.write("/tmp/*")
        let context = ToolContext(
            toolName: "Write",
            arguments: #"{"file_path": "/tmp/path with spaces/file.txt"}"#
        )

        #expect(rule.matches(context))
    }

    // MARK: - Glob and Grep Path Normalization

    @Test("Glob path normalization resolves ..")
    func testGlobPathNormalization() {
        let rule = PermissionRule("Glob(/etc/*)")
        // /var/../etc/passwd normalizes to /etc/passwd which matches /etc/*
        let context = ToolContext(
            toolName: "Glob",
            arguments: #"{"path": "/var/../etc/passwd"}"#
        )

        #expect(rule.matches(context), "/var/../etc/passwd should normalize to /etc/passwd")
    }

    @Test("Grep path normalization resolves ..")
    func testGrepPathNormalization() {
        let rule = PermissionRule("Grep(/etc/*)")
        let context = ToolContext(
            toolName: "Grep",
            arguments: #"{"path": "/var/../etc/passwd"}"#
        )

        #expect(rule.matches(context), "/var/../etc/passwd should normalize to /etc/passwd")
    }

    // MARK: - Very Long Paths

    @Test("Very long file path")
    func testVeryLongPath() {
        let rule = PermissionRule.write("/tmp/*")
        let longPath = "/tmp/" + String(repeating: "subdir/", count: 50) + "file.txt"
        let context = ToolContext(
            toolName: "Write",
            arguments: #"{"file_path": "\#(longPath)"}"#
        )

        #expect(rule.matches(context))
    }

    // MARK: - Exact Match vs Prefix Match

    @Test("Exact command match (no :*)")
    func testExactCommandMatch() {
        let rule = PermissionRule.bash("git status")
        let context1 = ToolContext(toolName: "Bash", arguments: #"{"command": "git status"}"#)
        let context2 = ToolContext(toolName: "Bash", arguments: #"{"command": "git status --short"}"#)

        #expect(rule.matches(context1), "Should match exact command")
        #expect(!rule.matches(context2), "Should NOT match with additional args")
    }

    @Test("Wildcard pattern vs prefix pattern")
    func testWildcardVsPrefix() {
        // Wildcard: git* matches anything starting with "git"
        let wildcardRule = PermissionRule("Bash(git*)")
        // Prefix: git:* requires separator after "git"
        let prefixRule = PermissionRule.bash("git:*")

        let contextNoSep = ToolContext(toolName: "Bash", arguments: #"{"command": "gitsomething"}"#)
        let contextWithSep = ToolContext(toolName: "Bash", arguments: #"{"command": "git status"}"#)

        // Wildcard matches both
        #expect(wildcardRule.matches(contextNoSep), "Wildcard should match 'gitsomething'")
        #expect(wildcardRule.matches(contextWithSep), "Wildcard should match 'git status'")

        // Prefix only matches with separator
        #expect(!prefixRule.matches(contextNoSep), "Prefix should NOT match 'gitsomething'")
        #expect(prefixRule.matches(contextWithSep), "Prefix should match 'git status'")
    }
}

// MARK: - Session Memory Tests

@Suite("Session Memory")
struct SessionMemoryTests {

    @Test("Session memory is disabled when enableSessionMemory is false")
    func testSessionMemoryDisabled() async throws {
        let config = PermissionConfiguration(
            allow: [],
            deny: [],
            defaultAction: .allow,
            enableSessionMemory: false
        )
        let middleware = PermissionMiddleware(configuration: config)

        // Execute once
        let context = ToolContext(toolName: "Read", arguments: #"{"file_path": "/tmp/test"}"#)
        _ = try await middleware.handle(context) { _ in
            ToolResult.success("ok", duration: .zero)
        }

        // Session memory should be empty
        #expect(middleware.alwaysAllowedPatterns.isEmpty)
        #expect(middleware.blockedPatterns.isEmpty)
    }

    @Test("Reset session memory clears all patterns")
    func testResetSessionMemory() async throws {
        let config = PermissionConfiguration(
            allow: [.tool("Read")],
            deny: [],
            defaultAction: .allow,
            enableSessionMemory: true
        )
        let middleware = PermissionMiddleware(configuration: config)

        // Execute to potentially populate memory
        let context = ToolContext(toolName: "Read", arguments: #"{"file_path": "/tmp/test"}"#)
        _ = try await middleware.handle(context) { _ in
            ToolResult.success("ok", duration: .zero)
        }

        // Reset
        middleware.resetSessionMemory()

        #expect(middleware.alwaysAllowedPatterns.isEmpty)
        #expect(middleware.blockedPatterns.isEmpty)
    }

    @Test("FinalDeny checked before session memory")
    func testFinalDenyBeforeSessionMemoryIntegration() async throws {
        // Even if a pattern was previously "always allowed" in session memory,
        // finalDeny should still block it.
        // This is verified by the fact that finalDeny is checked first in evaluation order.

        let config = PermissionConfiguration(
            allow: [.bash("sudo:*")],  // Allow sudo (would go to session memory if asked)
            finalDeny: [.bash("sudo:*")],  // But finalDeny blocks it
            defaultAction: .allow,
            enableSessionMemory: true
        )
        let middleware = PermissionMiddleware(configuration: config)

        let context = ToolContext(
            toolName: "Bash",
            arguments: #"{"command": "sudo whoami"}"#
        )

        // First attempt - should be blocked by finalDeny
        await #expect(throws: PermissionDenied.self) {
            _ = try await middleware.handle(context) { _ in
                ToolResult.success("root", duration: .zero)
            }
        }

        // Second attempt - still blocked (finalDeny evaluated before session memory)
        await #expect(throws: PermissionDenied.self) {
            _ = try await middleware.handle(context) { _ in
                ToolResult.success("root", duration: .zero)
            }
        }
    }
}

// MARK: - Performance Tests

@Suite("Performance")
struct PerformanceTests {

    @Test("Many rules evaluation")
    func testManyRulesPerformance() async throws {
        // Create configuration with many rules
        var allowRules: [PermissionRule] = []
        var denyRules: [PermissionRule] = []

        for i in 0..<100 {
            allowRules.append(.bash("allowed_cmd_\(i):*"))
            denyRules.append(.bash("denied_cmd_\(i):*"))
        }

        let config = PermissionConfiguration(
            allow: allowRules,
            deny: denyRules,
            defaultAction: .deny
        )
        let middleware = PermissionMiddleware(configuration: config)

        // Test that matching still works correctly
        let allowedContext = ToolContext(
            toolName: "Bash",
            arguments: #"{"command": "allowed_cmd_50 arg"}"#
        )
        let deniedContext = ToolContext(
            toolName: "Bash",
            arguments: #"{"command": "denied_cmd_50 arg"}"#
        )
        let unmatchedContext = ToolContext(
            toolName: "Bash",
            arguments: #"{"command": "unknown_cmd arg"}"#
        )

        // Allowed command should pass
        let result1 = try await middleware.handle(allowedContext) { _ in
            ToolResult.success("ok", duration: .zero)
        }
        #expect(result1.success)

        // Denied command should fail
        await #expect(throws: PermissionDenied.self) {
            _ = try await middleware.handle(deniedContext) { _ in
                ToolResult.success("ok", duration: .zero)
            }
        }

        // Unmatched command should fail (default is deny)
        await #expect(throws: PermissionDenied.self) {
            _ = try await middleware.handle(unmatchedContext) { _ in
                ToolResult.success("ok", duration: .zero)
            }
        }
    }

    @Test("Deeply nested path normalization")
    func testDeeplyNestedPathNormalization() {
        let rule = PermissionRule.write("/home/*")
        // Path that escapes to /home via .. components
        // /tmp/x/../../home/user/file.txt normalizes to /home/user/file.txt
        let escapePath = "/tmp/x/../../home/user/file.txt"
        let context = ToolContext(
            toolName: "Write",
            arguments: #"{"file_path": "\#(escapePath)"}"#
        )

        #expect(rule.matches(context), "\(escapePath) should normalize to /home/user/file.txt")
    }
}

// MARK: - Integration Test: Hierarchical Guardrails

@Suite("Hierarchical Guardrail Integration")
struct HierarchicalGuardrailTests {

    @Test("Nested guardrails merge correctly")
    func testNestedGuardrailsMerge() {
        // Simulate: Outer denies rm:*, Inner allows specific rm command
        let outer = GuardrailConfiguration(
            deny: [.bash("rm:*")],
            defaultAction: .allow
        )

        let inner = GuardrailConfiguration(
            overrides: [.bash("rm -i:*")]  // Allow rm -i (interactive)
        )

        let merged = outer.merged(with: inner)

        // Inner override should be present
        #expect(merged.overrides.contains(.bash("rm -i:*")))
        // Outer deny should still be present
        #expect(merged.deny.contains(.bash("rm:*")))
    }

    @Test("FinalDeny cannot be relaxed at any level")
    func testFinalDenyCannotBeRelaxed() async throws {
        // Root level sets finalDeny
        let root = GuardrailConfiguration(
            finalDeny: [.bash("sudo:*")]
        )

        // Child tries to override
        let child = GuardrailConfiguration(
            allow: [.bash("sudo:*")],
            overrides: [.bash("sudo:*")]
        )

        let merged = root.merged(with: child)
        let permConfig = merged.mergedPermissions(with: PermissionConfiguration(defaultAction: .allow))
        let middleware = PermissionMiddleware(configuration: permConfig)

        let context = ToolContext(
            toolName: "Bash",
            arguments: #"{"command": "sudo whoami"}"#
        )

        // Should still be denied despite override and allow
        await #expect(throws: PermissionDenied.self) {
            _ = try await middleware.handle(context) { _ in
                ToolResult.success("root", duration: .zero)
            }
        }
    }
}
