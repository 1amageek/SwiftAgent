import Foundation
import Testing
@testable import SwiftAgent
@testable import SwiftAgentPlugins

@Suite("Plugin Manager")
struct PluginManagerTests {

    @Test("Rejects Claude Code manifest-only fields")
    func rejectsClaudeCodeManifestOnlyFields() throws {
        let directory = try makeTemporaryDirectory()
        defer { removeDirectory(directory) }

        let manifest = """
        {
          "name": "bad-plugin",
          "version": "1.0.0",
          "description": "Bad plugin",
          "skills": ["./skills"]
        }
        """

        try manifest.write(
            to: URL(fileURLWithPath: directory).appendingPathComponent("plugin.json"),
            atomically: true,
            encoding: .utf8
        )

        do {
            _ = try PluginManager.loadManifest(fromDirectory: directory)
            Issue.record("Expected manifest validation to fail")
        } catch let error as PluginError {
            guard case .manifestValidation(let errors) = error else {
                Issue.record("Expected manifest validation error, got \(error)")
                return
            }
            #expect(errors.contains {
                if case .unsupportedManifestContract = $0 {
                    return true
                }
                return false
            })
        }
    }

    @Test("Loads external plugin tool definitions")
    func loadsExternalPluginToolDefinitions() throws {
        let directory = try makeTemporaryDirectory()
        defer { removeDirectory(directory) }

        let manifest = """
        {
          "name": "echo-tools",
          "version": "1.0.0",
          "description": "Echo tools",
          "defaultEnabled": true,
          "tools": [
            {
              "name": "echo_json",
              "description": "Echo JSON input",
              "inputSchema": {
                "type": "object",
                "properties": {
                  "message": {
                    "type": "string",
                    "description": "Message to echo"
                  }
                },
                "required": ["message"]
              },
              "command": "cat",
              "requiredPermission": "read-only"
            }
          ]
        }
        """

        try manifest.write(
            to: URL(fileURLWithPath: directory).appendingPathComponent("plugin.json"),
            atomically: true,
            encoding: .utf8
        )

        let manager = PluginManager(
            configuration: PluginManagerConfig(
                enabledPlugins: ["echo-tools@external": true],
                externalRoots: [directory]
            )
        )
        let tools = try manager.aggregatedTools()

        #expect(tools.count == 1)
        #expect(tools[0].pluginID == "echo-tools@external")
        #expect(tools[0].definition.name == "echo_json")
        #expect(tools[0].requiredPermission == .readOnly)
        #expect(tools[0].command == "cat")
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
}
