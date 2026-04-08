import Foundation
import Testing
@testable import SwiftAgent
@testable import SwiftAgentPlugins

@Suite("Plugin Manager State")
struct PluginStateTests {

    @Test("Install persists plugin registry and enables the plugin")
    func installPersistsRegistryAndEnabledState() throws {
        let configHome = try makeTemporaryDirectory()
        let sourceRoot = try makePluginSource(name: "demo-plugin", version: "1.0.0")
        defer {
            removeDirectory(configHome)
            removeDirectory(sourceRoot)
        }

        var manager = PluginManager(configuration: PluginManagerConfig(configHome: configHome))
        let outcome = try manager.install(source: sourceRoot)
        let installed = try manager.listInstalledPlugins()

        #expect(outcome.pluginID == "demo-plugin@external")
        #expect(installed.count == 1)
        #expect(installed[0].metadata.id == "demo-plugin@external")
        #expect(installed[0].enabled)
    }

    @Test("Disable and enable persist through settings reload")
    func disableAndEnablePersistThroughSettingsReload() throws {
        let configHome = try makeTemporaryDirectory()
        let sourceRoot = try makePluginSource(name: "demo-plugin", version: "1.0.0")
        defer {
            removeDirectory(configHome)
            removeDirectory(sourceRoot)
        }

        var manager = PluginManager(configuration: PluginManagerConfig(configHome: configHome))
        _ = try manager.install(source: sourceRoot)
        try manager.disable(pluginID: "demo-plugin@external")

        var reloaded = PluginManager(configuration: PluginManagerConfig(configHome: configHome))
        var installed = try reloaded.listInstalledPlugins()
        #expect(installed.count == 1)
        #expect(!installed[0].enabled)

        try reloaded.enable(pluginID: "demo-plugin@external")
        installed = try PluginManager(configuration: PluginManagerConfig(configHome: configHome))
            .listInstalledPlugins()
        #expect(installed.count == 1)
        #expect(installed[0].enabled)
    }

    @Test("Uninstall removes external plugin from registry and install root")
    func uninstallRemovesExternalPlugin() throws {
        let configHome = try makeTemporaryDirectory()
        let sourceRoot = try makePluginSource(name: "demo-plugin", version: "1.0.0")
        defer {
            removeDirectory(configHome)
            removeDirectory(sourceRoot)
        }

        var manager = PluginManager(configuration: PluginManagerConfig(configHome: configHome))
        let outcome = try manager.install(source: sourceRoot)

        try manager.uninstall(pluginID: "demo-plugin@external")

        let installed = try manager.listInstalledPlugins()
        #expect(installed.isEmpty)
        #expect(!FileManager.default.fileExists(atPath: outcome.installPath))
    }

    @Test("Bundled plugin sync copies bundled plugins into install root and lists them")
    func bundledPluginSyncCopiesIntoInstallRoot() throws {
        let configHome = try makeTemporaryDirectory()
        let bundledRoot = try makeTemporaryDirectory()
        let bundledPlugin = try makePluginSource(
            parent: bundledRoot,
            name: "starter",
            version: "1.0.0"
        )
        defer {
            removeDirectory(configHome)
            removeDirectory(bundledRoot)
            removeDirectory(bundledPlugin)
        }

        let manager = PluginManager(
            configuration: PluginManagerConfig(
                configHome: configHome,
                bundledRoots: [bundledRoot]
            )
        )

        let installed = try manager.listInstalledPlugins()

        #expect(installed.count == 1)
        #expect(installed[0].metadata.id == "starter@bundled")
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

    private func makePluginSource(
        parent: String? = nil,
        name: String,
        version: String
    ) throws -> String {
        let rootURL: URL
        if let parent {
            rootURL = URL(fileURLWithPath: parent).appendingPathComponent(name)
        } else {
            rootURL = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        }
        try FileManager.default.createDirectory(
            at: rootURL,
            withIntermediateDirectories: true,
            attributes: nil
        )

        let manifest = """
        {
          "name": "\(name)",
          "version": "\(version)",
          "description": "Test plugin",
          "defaultEnabled": true,
          "tools": [
            {
              "name": "echo_json",
              "description": "Echo JSON input",
              "inputSchema": {
                "type": "object",
                "properties": {
                  "message": { "type": "string" }
                }
              },
              "command": "cat",
              "requiredPermission": "read-only"
            }
          ]
        }
        """

        try manifest.write(
            to: rootURL.appendingPathComponent("plugin.json"),
            atomically: true,
            encoding: .utf8
        )
        return rootURL.path
    }

    private func removeDirectory(_ path: String) {
        do {
            if FileManager.default.fileExists(atPath: path) {
                try FileManager.default.removeItem(atPath: path)
            }
        } catch {
            Issue.record("Failed to remove temporary directory: \(error.localizedDescription)")
        }
    }
}
