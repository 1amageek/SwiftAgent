//
//  SkillRuntimeTests.swift
//  SwiftAgent
//

import Foundation
import Testing
@testable import SwiftAgent
@testable import SwiftAgentSkills

@Suite("SkillRuntime")
struct SkillRuntimeTests {

    @Test("Runtime exposes catalog and activation tool without full instructions")
    func runtimeExposesCatalogOnly() async throws {
        let fixture = try SkillFixture()
        defer { fixture.remove() }

        try fixture.writeSkill(
            name: "research",
            description: "Use for focused research tasks.",
            body: "FULL_SECRET_INSTRUCTIONS"
        )

        let runtime = try await SkillRuntime.prepare(
            SkillsConfiguration(autoDiscover: false, searchPaths: [fixture.skillsRoot])
        )

        #expect(runtime.hasSkills)
        #expect(runtime.tools.map(\.name) == [SkillTool.name])
        #expect(runtime.instructionsPrompt.contains("<skill_policy>"))
        #expect(runtime.instructionsPrompt.contains("<available_skills>"))
        #expect(runtime.instructionsPrompt.contains("<name>research</name>"))
        #expect(runtime.instructionsPrompt.contains("Use for focused research tasks."))
        #expect(!runtime.instructionsPrompt.contains("FULL_SECRET_INSTRUCTIONS"))
    }

    @Test("Skill activation loads instructions and grants dynamic permissions")
    func skillActivationLoadsInstructionsAndPermissions() async throws {
        let fixture = try SkillFixture()
        defer { fixture.remove() }

        try fixture.writeSkill(
            name: "workspace-read",
            description: "Use for workspace inspection.",
            allowedTools: "Read Grep",
            body: "Read relevant workspace files."
        )

        let permissions = SkillPermissions()
        let runtime = try await SkillRuntime.prepare(
            SkillsConfiguration(autoDiscover: false, searchPaths: [fixture.skillsRoot]),
            permissions: permissions
        )

        let output = try await runtime.skillTool.call(arguments: SkillToolArguments(
            skillName: "workspace-read"
        ))

        #expect(output.instructions == "Read relevant workspace files.")
        #expect(output.grantedPermissions == "Read Grep")
        #expect(Set(permissions.rules.map(\.pattern)) == Set(["Read", "Grep"]))
    }

    @Test("Runner configuration injects skill tool")
    func runnerConfigurationInjectsSkillTool() async throws {
        let fixture = try SkillFixture()
        defer { fixture.remove() }

        try fixture.writeSkill(
            name: "planning",
            description: "Use for task planning.",
            body: "Plan the task."
        )

        let configuration = try await AgentSessionRunnerConfiguration.withSkills(
            skills: SkillsConfiguration(autoDiscover: false, searchPaths: [fixture.skillsRoot])
        ) {
            Instructions("Base instructions.")
        } step: {
            Transform { (_: Prompt) in "ok" }
        }

        #expect(configuration.tools.map(\.name) == [SkillTool.name])
    }

    @Test("SkillLoader delegates standard frontmatter parsing to SwiftSkill")
    func skillLoaderSupportsStandardFrontmatter() throws {
        let fixture = try SkillFixture()
        defer { fixture.remove() }

        try fixture.writeRawSkill(
            name: "standard",
            content: """
            ---
            name: standard
            description: Use for standard agent skill files.
            metadata:
              owner: runtime
            allowed-tools:
              - Read
              - Grep
            ---

            Follow the standard skill body.
            """
        )

        let skill = try SkillLoader.loadFull(
            from: (fixture.skillsRoot as NSString).appendingPathComponent("standard")
        )

        #expect(skill.metadata.metadata == ["owner": "runtime"])
        #expect(skill.metadata.allowedTools == "Read Grep")
        #expect(skill.instructions == "Follow the standard skill body.")
    }

    @Test("SkillLoader keeps legacy markdown skill support")
    func skillLoaderKeepsLegacyMarkdownSupport() throws {
        let fixture = try SkillFixture()
        defer { fixture.remove() }

        let commandPath = (fixture.root as NSString).appendingPathComponent("legacy-command.md")
        try """
        # Legacy Command

        Use for legacy markdown command files.

        Follow legacy command instructions.
        """.write(toFile: commandPath, atomically: true, encoding: .utf8)

        let skill = try SkillLoader.loadFull(from: commandPath)

        #expect(skill.metadata.name == "legacy-command")
        #expect(skill.metadata.description == "Use for legacy markdown command files.")
        #expect(skill.instructions?.contains("Follow legacy command instructions.") == true)
    }
}

private struct SkillFixture {
    let root: String
    let skillsRoot: String

    init() throws {
        let rootURL = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("swift-agent-skills-\(UUID().uuidString)")
        root = rootURL.path
        skillsRoot = rootURL.appendingPathComponent("skills").path
        try FileManager.default.createDirectory(
            atPath: skillsRoot,
            withIntermediateDirectories: true
        )
    }

    func writeSkill(
        name: String,
        description: String,
        allowedTools: String? = nil,
        body: String
    ) throws {
        let skillPath = (skillsRoot as NSString).appendingPathComponent(name)
        try FileManager.default.createDirectory(
            atPath: skillPath,
            withIntermediateDirectories: true
        )

        var frontmatter = [
            "---",
            "name: \(name)",
            "description: \(description)",
        ]
        if let allowedTools {
            frontmatter.append("allowed-tools: \(allowedTools)")
        }
        frontmatter.append("---")

        let content = (frontmatter + ["", body]).joined(separator: "\n")
        let filePath = (skillPath as NSString).appendingPathComponent("SKILL.md")
        try content.write(toFile: filePath, atomically: true, encoding: .utf8)
    }

    func writeRawSkill(name: String, content: String) throws {
        let skillPath = (skillsRoot as NSString).appendingPathComponent(name)
        try FileManager.default.createDirectory(
            atPath: skillPath,
            withIntermediateDirectories: true
        )

        let filePath = (skillPath as NSString).appendingPathComponent("SKILL.md")
        try content.write(toFile: filePath, atomically: true, encoding: .utf8)
    }

    func remove() {
        do {
            try FileManager.default.removeItem(atPath: root)
        } catch {
            Issue.record("Failed to remove temporary skill fixture: \(error)")
        }
    }
}
