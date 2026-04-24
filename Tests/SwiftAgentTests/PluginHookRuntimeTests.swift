import Foundation
import Testing
@testable import SwiftAgent
@testable import SwiftAgentPlugins

private struct HookEchoInput: Sendable, Codable, Generable {
    let command: String

    init(command: String) {
        self.command = command
    }

    init(_ content: GeneratedContent) throws {
        guard let data = content.jsonString.data(using: .utf8) else {
            throw PluginError.json("Failed to decode HookEchoInput.")
        }
        self = try JSONDecoder().decode(Self.self, from: data)
    }

    var generatedContent: GeneratedContent {
        do {
            let data = try JSONEncoder().encode(self)
            guard let json = String(data: data, encoding: .utf8) else {
                fatalError("Failed to encode HookEchoInput.")
            }
            return try GeneratedContent(json: json)
        } catch {
            fatalError("Failed to encode HookEchoInput: \(error.localizedDescription)")
        }
    }

    static var generationSchema: GenerationSchema {
        do {
            return try GenerationSchema(
                root: DynamicGenerationSchema(
                    name: "HookEchoInput",
                    properties: [
                        DynamicGenerationSchema.Property(
                            name: "command",
                            description: "Command text",
                            schema: DynamicGenerationSchema(type: String.self, guides: []),
                            isOptional: false
                        )
                    ]
                ),
                dependencies: []
            )
        } catch {
            fatalError("Failed to build HookEchoInput schema: \(error.localizedDescription)")
        }
    }
}

private actor HookExecutionRecorder {
    private var commands: [String] = []

    func record(_ command: String) {
        commands.append(command)
    }

    func snapshot() -> [String] {
        commands
    }
}

private struct HookEchoTool: Tool {
    typealias Arguments = HookEchoInput
    typealias Output = String

    let recorder: HookExecutionRecorder

    var name: String { "hook_echo" }
    var description: String { "Echoes the incoming command" }

    func call(arguments: HookEchoInput) async throws -> String {
        await recorder.record(arguments.command)
        return arguments.command
    }
}

private enum HookFixtureError: Error {
    case exploded
}

private struct HookFailingTool: Tool {
    typealias Arguments = HookEchoInput
    typealias Output = String

    var name: String { "hook_fail" }
    var description: String { "Always fails" }

    func call(arguments: HookEchoInput) async throws -> String {
        throw HookFixtureError.exploded
    }
}

@Suite("Plugin Hook Runtime")
struct PluginHookRuntimeTests {

    @Test("Pre hook updatedInput rewrites typed tool arguments before execution")
    func preHookUpdatedInputRewritesTypedArguments() async throws {
        let temporaryDirectory = try makeTemporaryDirectory()
        defer { removeDirectory(temporaryDirectory) }

        let hookPath = try writeHook(
            in: temporaryDirectory,
            named: "pre.sh",
            body: #"printf '%s' '{"systemMessage":"updated","hookSpecificOutput":{"updatedInput":{"command":"git status"}}}'"#
        )

        let runner = PluginHookRunner(hooks: PluginHooks(preToolUse: [hookPath]))
        let recorder = HookExecutionRecorder()
        let tool = HookEchoTool(recorder: recorder)
        var config = ToolRuntimeConfiguration.empty
        config.use(PluginHookMiddleware(hookRunner: runner))
        config.register(tool)
        let runtime = ToolRuntime(configuration: config)

        let output = try await runtime.execute(tool, arguments: HookEchoInput(command: "pwd"))

        #expect(output == "git status")
        #expect(await recorder.snapshot() == ["git status"])
    }

    @Test("Pre hook denial short-circuits tool execution")
    func preHookDenialShortCircuitsExecution() async throws {
        let temporaryDirectory = try makeTemporaryDirectory()
        defer { removeDirectory(temporaryDirectory) }

        let hookPath = try writeHook(
            in: temporaryDirectory,
            named: "deny.sh",
            body: #"printf '%s' '{"reason":"blocked by hook","continue":false}'"#
        )

        let runner = PluginHookRunner(hooks: PluginHooks(preToolUse: [hookPath]))
        let recorder = HookExecutionRecorder()
        let tool = HookEchoTool(recorder: recorder)
        var config = ToolRuntimeConfiguration.empty
        config.use(PluginHookMiddleware(hookRunner: runner))
        config.register(tool)
        let runtime = ToolRuntime(configuration: config)

        await #expect(throws: PluginHookError.self) {
            _ = try await runtime.execute(tool, arguments: HookEchoInput(command: "pwd"))
        }
        #expect(await recorder.snapshot().isEmpty)
    }

    @Test("Post tool denial turns a successful tool result into an error")
    func postHookDenialConvertsSuccessToError() async throws {
        let temporaryDirectory = try makeTemporaryDirectory()
        defer { removeDirectory(temporaryDirectory) }

        let hookPath = try writeHook(
            in: temporaryDirectory,
            named: "post.sh",
            body: #"printf '%s' '{"reason":"post hook blocked","continue":false}'"#
        )

        let runner = PluginHookRunner(hooks: PluginHooks(postToolUse: [hookPath]))
        let recorder = HookExecutionRecorder()
        let tool = HookEchoTool(recorder: recorder)
        var config = ToolRuntimeConfiguration.empty
        config.use(PluginHookMiddleware(hookRunner: runner))
        config.register(tool)
        let runtime = ToolRuntime(configuration: config)

        await #expect(throws: PluginHookError.self) {
            _ = try await runtime.execute(tool, arguments: HookEchoInput(command: "pwd"))
        }
        #expect(await recorder.snapshot() == ["pwd"])
    }

    @Test("Post tool failure hook runs when the tool throws")
    func postFailureHookRunsOnToolError() async throws {
        let temporaryDirectory = try makeTemporaryDirectory()
        defer { removeDirectory(temporaryDirectory) }

        let markerPath = URL(fileURLWithPath: temporaryDirectory)
            .appendingPathComponent("marker.txt")
            .path
        let hookPath = try writeHook(
            in: temporaryDirectory,
            named: "failure.sh",
            body: "printf 'failure hook ran' > '\(markerPath)'"
        )

        let runner = PluginHookRunner(hooks: PluginHooks(postToolUseFailure: [hookPath]))
        let tool = HookFailingTool()
        var config = ToolRuntimeConfiguration.empty
        config.use(PluginHookMiddleware(hookRunner: runner))
        config.register(tool)
        let runtime = ToolRuntime(configuration: config)

        await #expect(throws: HookFixtureError.self) {
            _ = try await runtime.execute(tool, arguments: HookEchoInput(command: "false"))
        }

        let marker = try String(contentsOfFile: markerPath, encoding: .utf8)
        #expect(marker == "failure hook ran")
    }

    @Test("Hook runner parses permission override and updated input from JSON output")
    func hookRunnerParsesStructuredOutput() async throws {
        let temporaryDirectory = try makeTemporaryDirectory()
        defer { removeDirectory(temporaryDirectory) }

        let hookPath = try writeHook(
            in: temporaryDirectory,
            named: "structured.sh",
            body: #"printf '%s' '{"systemMessage":"updated","hookSpecificOutput":{"permissionDecision":"allow","permissionDecisionReason":"hook ok","updatedInput":{"command":"git status"}}}'"#
        )

        let runner = PluginHookRunner(hooks: PluginHooks(preToolUse: [hookPath]))
        let result = try await runner.runPreToolUse(
            toolName: "Bash",
            toolInput: #"{"command":"pwd"}"#
        )

        #expect(result.authorizationDecision == .allow)
        #expect(result.authorizationReason == "hook ok")
        #expect(result.updatedInput == #"{"command":"git status"}"#)
        #expect(result.messages.contains("updated"))
    }

    private func makeTemporaryDirectory() throws -> String {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(
            at: directory,
            withIntermediateDirectories: true,
            attributes: nil
        )
        return directory.path
    }

    private func removeDirectory(_ path: String) {
        do {
            try FileManager.default.removeItem(atPath: path)
        } catch {
            Issue.record("Failed to remove temporary directory: \(error.localizedDescription)")
        }
    }

    private func writeHook(
        in directory: String,
        named name: String,
        body: String
    ) throws -> String {
        let path = URL(fileURLWithPath: directory).appendingPathComponent(name).path
        let script = """
        #!/bin/sh
        set -eu
        \(body)
        """
        try script.write(toFile: path, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes(
            [.posixPermissions: 0o755],
            ofItemAtPath: path
        )
        return path
    }
}
