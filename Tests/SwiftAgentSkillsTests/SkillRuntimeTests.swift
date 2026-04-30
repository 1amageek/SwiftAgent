//
//  SkillRuntimeTests.swift
//  SwiftAgent
//

import Foundation
import Synchronization
import Testing
@testable import SwiftAgent
@testable import SwiftAgentSkills

#if OpenFoundationModels
import OpenFoundationModels
#endif

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

    @Test("SkillLoader supports legacy command frontmatter without name")
    func skillLoaderSupportsLegacyCommandFrontmatterWithoutName() throws {
        let fixture = try SkillFixture()
        defer { fixture.remove() }

        let commandPath = (fixture.root as NSString).appendingPathComponent("codex-review.md")
        try """
        ---
        description: Run code review using OpenAI Codex CLI
        ---

        Execute the review workflow.
        """.write(toFile: commandPath, atomically: true, encoding: .utf8)

        let skill = try SkillLoader.loadFull(from: commandPath)

        #expect(skill.metadata.name == "codex-review")
        #expect(skill.metadata.description == "Run code review using OpenAI Codex CLI")
        #expect(skill.instructions == "Execute the review workflow.")
    }

    @Test("SkillLoader normalizes mismatched directory skill names")
    func skillLoaderNormalizesMismatchedDirectorySkillNames() throws {
        let fixture = try SkillFixture()
        defer { fixture.remove() }

        try fixture.writeRawSkill(
            name: "mlx-swift",
            content: """
            ---
            name: swift-mlx
            description: Use for MLX Swift development.
            ---

            Follow MLX Swift guidance.
            """
        )

        let skill = try SkillLoader.loadFull(
            from: (fixture.skillsRoot as NSString).appendingPathComponent("mlx-swift")
        )

        #expect(skill.metadata.name == "mlx-swift")
        #expect(skill.metadata.description == "Use for MLX Swift development.")
        #expect(skill.instructions == "Follow MLX Swift guidance.")
    }

    @Test("Skill activation preserves normalized directory skill names")
    func skillActivationPreservesNormalizedDirectorySkillNames() async throws {
        let fixture = try SkillFixture()
        defer { fixture.remove() }

        try fixture.writeRawSkill(
            name: "mlx-swift",
            content: """
            ---
            name: swift-mlx
            description: Use for MLX Swift development.
            ---

            Follow MLX Swift guidance.
            """
        )

        let runtime = try await SkillRuntime.prepare(
            SkillsConfiguration(autoDiscover: false, searchPaths: [fixture.skillsRoot])
        )
        let output = try await runtime.skillTool.call(arguments: SkillToolArguments(
            skillName: "mlx-swift"
        ))

        #expect(output.skillName == "mlx-swift")
        #expect(output.instructions == "Follow MLX Swift guidance.")
    }

    #if OpenFoundationModels
    @Test("Skill activation grants permissions used by a later tool call in the same session")
    func skillActivationGrantsPermissionsForSameSessionToolCall() async throws {
        let fixture = try SkillFixture()
        defer { fixture.remove() }

        try fixture.writeSkill(
            name: "workspace-writer",
            description: "Use for workspace updates.",
            allowedTools: "WorkspaceWrite",
            body: "Use the workspace write tool when requested."
        )

        let permissions = SkillPermissions()
        let skillRuntime = try await SkillRuntime.prepare(
            SkillsConfiguration(autoDiscover: false, searchPaths: [fixture.skillsRoot]),
            permissions: permissions
        )

        var runtimeConfiguration = ToolRuntimeConfiguration.empty
        runtimeConfiguration.use(PermissionMiddleware(configuration: PermissionConfiguration(
            allow: [.tool(SkillTool.name)],
            defaultAction: .deny,
            enableSessionMemory: false
        )))
        runtimeConfiguration = skillRuntime.applying(to: runtimeConfiguration)
        runtimeConfiguration.register(skillRuntime.tools)

        let writeLog = WorkspaceWriteLog()
        runtimeConfiguration.register(WorkspaceWriteTool(log: writeLog))
        let runtime = ToolRuntime(configuration: runtimeConfiguration)

        let model = SkillActivationModel()
        let session = LanguageModelSession(
            model: model,
            tools: runtime.publicTools(),
            instructions: skillRuntime.instructionsPrompt
        )

        let response = try await session.respond(to: "Update the workspace.")

        #expect(response.content == "workspace update completed")
        #expect(writeLog.messages == ["approved payload"])
        #expect(Set(permissions.rules.map(\.pattern)) == ["WorkspaceWrite"])
        #expect(model.transcripts.count == 3)
    }
    #endif
}

#if OpenFoundationModels
private final class WorkspaceWriteLog: Sendable {
    private let storage = Mutex<[String]>([])

    var messages: [String] {
        storage.withLock { $0 }
    }

    func append(_ message: String) {
        storage.withLock { $0.append(message) }
    }
}

private struct WorkspaceWriteTool: Tool {
    let name = "WorkspaceWrite"
    let description = "Writes a workspace update."
    let log: WorkspaceWriteLog

    @Generable
    struct Arguments: Sendable {
        @Guide(description: "Update content")
        let message: String
    }

    typealias Output = String

    func call(arguments: Arguments) async throws -> String {
        log.append(arguments.message)
        return "wrote \(arguments.message)"
    }
}

private final class SkillActivationModel: LanguageModel, Sendable {
    private let storage = Mutex<[Transcript]>([])

    var transcripts: [Transcript] {
        storage.withLock { $0 }
    }

    var isAvailable: Bool { true }
    func supports(locale: Locale) -> Bool { true }

    func generate(transcript: Transcript, options: GenerationOptions?) async throws -> Transcript.Entry {
        storage.withLock { $0.append(transcript) }

        let outputNames = transcript.compactMap { entry -> String? in
            if case .toolOutput(let output) = entry {
                return output.toolName
            }
            return nil
        }

        if !outputNames.contains(SkillTool.name) {
            return .toolCalls(Transcript.ToolCalls([
                Transcript.ToolCall(
                    id: UUID().uuidString,
                    toolName: SkillTool.name,
                    arguments: GeneratedContent(properties: [
                        "skillName": "workspace-writer",
                    ])
                )
            ]))
        }

        if !outputNames.contains("WorkspaceWrite") {
            return .toolCalls(Transcript.ToolCalls([
                Transcript.ToolCall(
                    id: UUID().uuidString,
                    toolName: "WorkspaceWrite",
                    arguments: GeneratedContent(properties: [
                        "message": "approved payload",
                    ])
                )
            ]))
        }

        return .response(Transcript.Response(
            id: UUID().uuidString,
            assetIDs: [],
            segments: [.text(Transcript.TextSegment(
                id: UUID().uuidString,
                content: "workspace update completed"
            ))]
        ))
    }

    func stream(transcript: Transcript, options: GenerationOptions?) -> AsyncThrowingStream<Transcript.Entry, Error> {
        AsyncThrowingStream { continuation in
            Task {
                do {
                    continuation.yield(try await generate(transcript: transcript, options: options))
                    continuation.finish()
                } catch {
                    continuation.finish(throwing: error)
                }
            }
        }
    }
}
#endif

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
