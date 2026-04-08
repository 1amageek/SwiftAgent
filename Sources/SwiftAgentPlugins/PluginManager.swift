//
//  PluginManager.swift
//  SwiftAgent
//
//  Created by SwiftAgent on 2026/04/08.
//

import Foundation
import SwiftAgent

/// Loads runtime plugins using the same manifest contract as `claw-code`.
public struct PluginManager: Sendable {
    public static let manifestFileName = "plugin.json"
    public static let manifestRelativePath = ".claude-plugin/plugin.json"

    public var configuration: PluginManagerConfig

    public init(configuration: PluginManagerConfig = PluginManagerConfig()) {
        self.configuration = configuration
    }

    public func loadRegistryReport() throws -> PluginRegistryReport {
        try pluginRegistryReport()
    }

    public func pluginRegistryReport() throws -> PluginRegistryReport {
        try syncBundledPlugins()

        var discovery = PluginDiscovery()
        var seenIDs = Set<String>()

        discovery.merge(try discoverPluginsWithFailures(
            roots: configuration.builtinRoots,
            kind: .builtin,
            seenIDs: &seenIDs
        ))
        discovery.merge(try discoverInstalledPluginsWithFailures(seenIDs: &seenIDs))
        discovery.merge(try discoverPluginsWithFailures(
            roots: configuration.externalRoots,
            kind: .external,
            seenIDs: &seenIDs
        ))

        return buildRegistryReport(discovery)
    }

    public func installedPluginRegistryReport() throws -> PluginRegistryReport {
        try syncBundledPlugins()
        var seenIDs = Set<String>()
        return buildRegistryReport(try discoverInstalledPluginsWithFailures(seenIDs: &seenIDs))
    }

    public func listPlugins() throws -> [PluginSummary] {
        try pluginRegistryReport().intoRegistry().summaries()
    }

    public func listInstalledPlugins() throws -> [PluginSummary] {
        try installedPluginRegistryReport().intoRegistry().summaries()
    }

    public func discoverPlugins() throws -> [PluginDefinition] {
        try pluginRegistryReport().intoRegistry().plugins.map(\.definition)
    }

    public func aggregatedHooks() throws -> PluginHooks {
        try pluginRegistryReport().intoRegistry().aggregatedHooks()
    }

    public func aggregatedTools() throws -> [PluginTool] {
        try pluginRegistryReport().intoRegistry().aggregatedTools()
    }

    public func aggregatedSwiftAgentTools() throws -> [any Tool] {
        try aggregatedTools().swiftAgentTools()
    }

    public func validatePluginSource(_ source: String) throws -> PluginManifest {
        let installSource = try parseInstallSource(source)
        let sourceRoot = switch installSource {
        case .localPath(let path):
            Self.expandPath(path)
        case .gitURL:
            throw PluginError.notFound("Plugin source `\(source)` must be materialized before validation.")
        }
        return try Self.loadManifest(fromDirectory: sourceRoot)
    }

    public mutating func install(source: String) throws -> PluginInstallOutcome {
        let installSource = try parseInstallSource(source)
        let stagedSource = try materializeSource(installSource, temporaryRoot: temporaryInstallRoot())
        defer { cleanupTemporarySourceIfNeeded(stagedSource, source: installSource) }

        let manifest = try Self.loadManifest(fromDirectory: stagedSource)
        let pluginID = Self.pluginIdentifier(name: manifest.name, marketplace: PluginKind.external.marketplace)
        let installPath = URL(fileURLWithPath: installRootPath())
            .appendingPathComponent(Self.sanitizePluginID(pluginID))
            .path

        try removeItemIfExists(atPath: installPath)
        try copyDirectory(from: stagedSource, to: installPath)

        let now = Self.unixTimeMilliseconds()
        var registry = try loadRegistry()
        registry.plugins[pluginID] = InstalledPluginRecord(
            kind: .external,
            id: pluginID,
            name: manifest.name,
            version: manifest.version,
            description: manifest.description,
            installPath: installPath,
            source: installSource,
            installedAtUnixMS: now,
            updatedAtUnixMS: now
        )
        try storeRegistry(registry)
        try writeEnabledState(pluginID: pluginID, enabled: true)
        configuration.enabledPlugins[pluginID] = true

        return PluginInstallOutcome(
            pluginID: pluginID,
            version: manifest.version,
            installPath: installPath
        )
    }

    public mutating func update(pluginID: String) throws -> PluginUpdateOutcome {
        var registry = try loadRegistry()
        guard let record = registry.plugins[pluginID] else {
            throw PluginError.notFound("plugin `\(pluginID)` is not installed")
        }

        let stagedSource = try materializeSource(record.source, temporaryRoot: temporaryInstallRoot())
        defer { cleanupTemporarySourceIfNeeded(stagedSource, source: record.source) }

        let manifest = try Self.loadManifest(fromDirectory: stagedSource)
        try removeItemIfExists(atPath: record.installPath)
        try copyDirectory(from: stagedSource, to: record.installPath)

        registry.plugins[pluginID] = InstalledPluginRecord(
            kind: record.kind,
            id: record.id,
            name: manifest.name,
            version: manifest.version,
            description: manifest.description,
            installPath: record.installPath,
            source: record.source,
            installedAtUnixMS: record.installedAtUnixMS,
            updatedAtUnixMS: Self.unixTimeMilliseconds()
        )
        try storeRegistry(registry)

        return PluginUpdateOutcome(
            pluginID: pluginID,
            oldVersion: record.version,
            newVersion: manifest.version,
            installPath: record.installPath
        )
    }

    public mutating func enable(pluginID: String) throws {
        try ensureKnownPlugin(pluginID)
        try writeEnabledState(pluginID: pluginID, enabled: true)
        configuration.enabledPlugins[pluginID] = true
    }

    public mutating func disable(pluginID: String) throws {
        try ensureKnownPlugin(pluginID)
        try writeEnabledState(pluginID: pluginID, enabled: false)
        configuration.enabledPlugins[pluginID] = false
    }

    public mutating func uninstall(pluginID: String) throws {
        var registry = try loadRegistry()
        guard let record = registry.plugins[pluginID] else {
            throw PluginError.notFound("plugin `\(pluginID)` is not installed")
        }
        if record.kind == .bundled {
            throw PluginError.commandFailed(
                "plugin `\(pluginID)` is bundled and managed automatically; disable it instead"
            )
        }

        registry.plugins.removeValue(forKey: pluginID)
        try storeRegistry(registry)
        try writeEnabledState(pluginID: pluginID, enabled: nil)
        configuration.enabledPlugins.removeValue(forKey: pluginID)
        try removeItemIfExists(atPath: record.installPath)
    }

    public func installRootPath() -> String {
        if let installRoot = configuration.installRoot {
            return Self.expandPath(installRoot)
        }
        return URL(fileURLWithPath: Self.expandPath(configuration.configHome))
            .appendingPathComponent("plugins/installed")
            .path
    }

    public func registryFilePath() -> String {
        if let registryPath = configuration.registryPath {
            return Self.expandPath(registryPath)
        }
        return URL(fileURLWithPath: Self.expandPath(configuration.configHome))
            .appendingPathComponent("plugins/installed.json")
            .path
    }

    public func settingsPath() -> String {
        URL(fileURLWithPath: Self.expandPath(configuration.configHome))
            .appendingPathComponent("settings.json")
            .path
    }

    public static func loadPluginDefinition(
        rootPath: String,
        kind: PluginKind,
        source: String
    ) throws -> PluginDefinition {
        let manifest = try loadManifest(fromDirectory: rootPath)
        let pluginID = pluginIdentifier(name: manifest.name, marketplace: kind.marketplace)
        let resolvedHooks = resolve(entries: manifest.hooks, relativeTo: rootPath)
        let resolvedLifecycle = resolve(entries: manifest.lifecycle, relativeTo: rootPath)
        let tools = resolve(
            manifests: manifest.tools,
            pluginID: pluginID,
            pluginName: manifest.name,
            rootPath: rootPath
        )

        let metadata = PluginMetadata(
            id: pluginID,
            name: manifest.name,
            version: manifest.version,
            description: manifest.description,
            kind: kind,
            source: source,
            defaultEnabled: manifest.defaultEnabled,
            rootPath: rootPath
        )

        return PluginDefinition(
            metadata: metadata,
            hooks: resolvedHooks,
            lifecycle: resolvedLifecycle,
            tools: tools
        )
    }

    public static func loadManifest(fromDirectory rootPath: String) throws -> PluginManifest {
        let manifestPath = try pluginManifestPath(rootPath: rootPath)
        let data: Data
        do {
            data = try Data(contentsOf: URL(fileURLWithPath: manifestPath))
        } catch {
            throw PluginError.io(path: manifestPath, reason: error.localizedDescription)
        }

        let rawJSON: Any
        do {
            rawJSON = try JSONSerialization.jsonObject(with: data)
        } catch {
            throw PluginError.json("Failed to parse plugin manifest at `\(manifestPath)`: \(error.localizedDescription)")
        }

        guard let rootObject = rawJSON as? [String: Any] else {
            throw PluginError.invalidManifest("plugin manifest at `\(manifestPath)` must be a JSON object")
        }

        let compatibilityErrors = detectClawCodeManifestContractGaps(rootObject)
        if !compatibilityErrors.isEmpty {
            throw PluginError.manifestValidation(compatibilityErrors)
        }

        let decoder = JSONDecoder()
        let rawManifest: RawPluginManifest
        do {
            rawManifest = try decoder.decode(RawPluginManifest.self, from: data)
        } catch {
            throw PluginError.json("Failed to decode plugin manifest at `\(manifestPath)`: \(error.localizedDescription)")
        }

        return try buildPluginManifest(rootPath: rootPath, raw: rawManifest)
    }

    private func discoverPluginsWithFailures(
        roots: [String],
        kind: PluginKind,
        seenIDs: inout Set<String>
    ) throws -> PluginDiscovery {
        var discovery = PluginDiscovery()

        for root in roots {
            for pluginRoot in try discoverPluginDirs(at: Self.expandPath(root)) {
                let source = pluginRoot
                do {
                    let plugin = try Self.loadPluginDefinition(
                        rootPath: pluginRoot,
                        kind: kind,
                        source: source
                    )
                    if seenIDs.insert(plugin.metadata.id).inserted {
                        discovery.plugins.append(plugin)
                    }
                } catch let error as PluginError {
                    discovery.failures.append(
                        PluginLoadFailure(
                            pluginRoot: pluginRoot,
                            kind: kind,
                            source: source,
                            message: error.localizedDescription
                        )
                    )
                } catch {
                    discovery.failures.append(
                        PluginLoadFailure(
                            pluginRoot: pluginRoot,
                            kind: kind,
                            source: source,
                            message: error.localizedDescription
                        )
                    )
                }
            }
        }

        return discovery
    }

    private func discoverInstalledPluginsWithFailures(
        seenIDs: inout Set<String>
    ) throws -> PluginDiscovery {
        var registry = try loadRegistry()
        var discovery = PluginDiscovery()
        let pluginRoots = try discoverPluginDirs(at: installRootPath())
        let pluginRootsSet = Set(pluginRoots.map(Self.standardizePath))

        for pluginRoot in pluginRoots {
            let matchingRecord = registry.plugins.values.first {
                Self.standardizePath($0.installPath) == Self.standardizePath(pluginRoot)
            }
            let kind = matchingRecord?.kind ?? .external
            let source = matchingRecord?.source.description ?? pluginRoot

            do {
                let plugin = try Self.loadPluginDefinition(
                    rootPath: pluginRoot,
                    kind: kind,
                    source: source
                )
                if seenIDs.insert(plugin.metadata.id).inserted {
                    discovery.plugins.append(plugin)
                }
            } catch let error as PluginError {
                discovery.failures.append(
                    PluginLoadFailure(
                        pluginRoot: pluginRoot,
                        kind: kind,
                        source: source,
                        message: error.localizedDescription
                    )
                )
            } catch {
                discovery.failures.append(
                    PluginLoadFailure(
                        pluginRoot: pluginRoot,
                        kind: kind,
                        source: source,
                        message: error.localizedDescription
                    )
                )
            }
        }

        var staleIDs: [String] = []
        for record in registry.plugins.values where !pluginRootsSet.contains(Self.standardizePath(record.installPath)) {
            if FileManager.default.fileExists(atPath: record.installPath),
               (try? Self.pluginManifestPath(rootPath: record.installPath)) != nil {
                do {
                    let plugin = try Self.loadPluginDefinition(
                        rootPath: record.installPath,
                        kind: record.kind,
                        source: record.source.description
                    )
                    if seenIDs.insert(plugin.metadata.id).inserted {
                        discovery.plugins.append(plugin)
                    }
                } catch let error as PluginError {
                    discovery.failures.append(
                        PluginLoadFailure(
                            pluginRoot: record.installPath,
                            kind: record.kind,
                            source: record.source.description,
                            message: error.localizedDescription
                        )
                    )
                } catch {
                    discovery.failures.append(
                        PluginLoadFailure(
                            pluginRoot: record.installPath,
                            kind: record.kind,
                            source: record.source.description,
                            message: error.localizedDescription
                        )
                    )
                }
            } else {
                staleIDs.append(record.id)
            }
        }

        if !staleIDs.isEmpty {
            for pluginID in staleIDs {
                registry.plugins.removeValue(forKey: pluginID)
            }
            try storeRegistry(registry)
        }

        return discovery
    }

    private func syncBundledPlugins() throws {
        guard !configuration.bundledRoots.isEmpty else {
            return
        }

        let installRoot = installRootPath()
        let fileManager = FileManager.default
        try fileManager.createDirectory(
            at: URL(fileURLWithPath: installRoot),
            withIntermediateDirectories: true,
            attributes: nil
        )

        var registry = try loadRegistry()
        var activeBundledIDs = Set<String>()
        var didChange = false

        for bundledRoot in configuration.bundledRoots {
            for sourceRoot in try discoverPluginDirs(at: Self.expandPath(bundledRoot)) {
                let manifest = try Self.loadManifest(fromDirectory: sourceRoot)
                let pluginID = Self.pluginIdentifier(name: manifest.name, marketplace: PluginKind.bundled.marketplace)
                activeBundledIDs.insert(pluginID)
                let destination = URL(fileURLWithPath: installRoot)
                    .appendingPathComponent(Self.sanitizePluginID(pluginID))
                    .path
                let existing = registry.plugins[pluginID]
                let now = Self.unixTimeMilliseconds()

                let needsSync = existing == nil
                    || existing?.kind != .bundled
                    || existing?.version != manifest.version
                    || existing?.name != manifest.name
                    || existing?.description != manifest.description
                    || existing?.installPath != destination
                    || !fileManager.fileExists(atPath: destination)

                if needsSync {
                    try removeItemIfExists(atPath: destination)
                    try copyDirectory(from: sourceRoot, to: destination)
                    registry.plugins[pluginID] = InstalledPluginRecord(
                        kind: .bundled,
                        id: pluginID,
                        name: manifest.name,
                        version: manifest.version,
                        description: manifest.description,
                        installPath: destination,
                        source: .localPath(path: sourceRoot),
                        installedAtUnixMS: existing?.installedAtUnixMS ?? now,
                        updatedAtUnixMS: now
                    )
                    didChange = true
                }
            }
        }

        let staleBundledIDs = registry.plugins.values
            .filter { $0.kind == .bundled && !activeBundledIDs.contains($0.id) }
            .map(\.id)
        for pluginID in staleBundledIDs {
            if let record = registry.plugins.removeValue(forKey: pluginID) {
                try removeItemIfExists(atPath: record.installPath)
                didChange = true
            }
        }

        if didChange {
            try storeRegistry(registry)
        }
    }

    private func buildRegistryReport(_ discovery: PluginDiscovery) -> PluginRegistryReport {
        let enabledPlugins = effectiveEnabledPlugins()
        let registry = PluginRegistry(
            plugins: discovery.plugins.map { plugin in
                let enabled = enabledPlugins[plugin.metadata.id] ?? defaultEnabled(for: plugin.metadata)
                return RegisteredPlugin(definition: plugin, enabled: enabled)
            }
        )
        return PluginRegistryReport(registry: registry, failures: discovery.failures)
    }

    private func defaultEnabled(for metadata: PluginMetadata) -> Bool {
        switch metadata.kind {
        case .external:
            return false
        case .builtin, .bundled:
            return metadata.defaultEnabled
        }
    }

    private func effectiveEnabledPlugins() -> [String: Bool] {
        loadEnabledPlugins(from: settingsPath()).merging(configuration.enabledPlugins) { _, new in new }
    }

    private func ensureKnownPlugin(_ pluginID: String) throws {
        if try pluginRegistryReport().intoRegistry().contains(pluginID) {
            return
        }
        throw PluginError.notFound("plugin `\(pluginID)` is not installed or discoverable")
    }

    private func loadRegistry() throws -> InstalledPluginRegistry {
        let path = registryFilePath()
        guard FileManager.default.fileExists(atPath: path) else {
            return InstalledPluginRegistry()
        }
        let data: Data
        do {
            data = try Data(contentsOf: URL(fileURLWithPath: path))
        } catch {
            throw PluginError.io(path: path, reason: error.localizedDescription)
        }
        if data.isEmpty {
            return InstalledPluginRegistry()
        }
        do {
            return try JSONDecoder().decode(InstalledPluginRegistry.self, from: data)
        } catch {
            throw PluginError.json("Failed to decode installed plugin registry at `\(path)`: \(error.localizedDescription)")
        }
    }

    private func storeRegistry(_ registry: InstalledPluginRegistry) throws {
        let path = registryFilePath()
        try FileManager.default.createDirectory(
            at: URL(fileURLWithPath: path).deletingLastPathComponent(),
            withIntermediateDirectories: true,
            attributes: nil
        )
        let data: Data
        do {
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            data = try encoder.encode(registry)
        } catch {
            throw PluginError.json("Failed to encode installed plugin registry: \(error.localizedDescription)")
        }
        do {
            try data.write(to: URL(fileURLWithPath: path))
        } catch {
            throw PluginError.io(path: path, reason: error.localizedDescription)
        }
    }

    private func writeEnabledState(
        pluginID: String,
        enabled: Bool?
    ) throws {
        let path = settingsPath()
        var root = loadSettingsRoot(from: path)
        var enabledPlugins = root["enabledPlugins"] as? [String: Any] ?? [:]
        enabledPlugins[pluginID] = enabled
        if enabled == nil {
            enabledPlugins.removeValue(forKey: pluginID)
        }
        root["enabledPlugins"] = enabledPlugins

        let data = try JSONSerialization.data(withJSONObject: root, options: [.prettyPrinted, .sortedKeys])
        try FileManager.default.createDirectory(
            at: URL(fileURLWithPath: path).deletingLastPathComponent(),
            withIntermediateDirectories: true,
            attributes: nil
        )
        try data.write(to: URL(fileURLWithPath: path))
    }

    private func loadSettingsRoot(from path: String) -> [String: Any] {
        guard let data = try? Data(contentsOf: URL(fileURLWithPath: path)),
              !data.isEmpty,
              let value = try? JSONSerialization.jsonObject(with: data),
              let root = value as? [String: Any] else {
            return [:]
        }
        return root
    }

    private func loadEnabledPlugins(from path: String) -> [String: Bool] {
        let root = loadSettingsRoot(from: path)
        guard let rawMap = root["enabledPlugins"] as? [String: Any] else {
            return [:]
        }
        var result: [String: Bool] = [:]
        for (pluginID, rawValue) in rawMap {
            if let boolValue = rawValue as? Bool {
                result[pluginID] = boolValue
            }
        }
        return result
    }

    private func parseInstallSource(_ source: String) throws -> PluginInstallSource {
        let expanded = Self.expandPath(source)
        var isDirectory: ObjCBool = false
        if FileManager.default.fileExists(atPath: expanded, isDirectory: &isDirectory), isDirectory.boolValue {
            return .localPath(path: expanded)
        }
        if source.hasPrefix("http://")
            || source.hasPrefix("https://")
            || source.hasPrefix("ssh://")
            || source.hasPrefix("git@")
            || source.hasSuffix(".git") {
            return .gitURL(url: source)
        }
        throw PluginError.notFound("plugin source `\(source)` does not exist")
    }

    private func materializeSource(
        _ source: PluginInstallSource,
        temporaryRoot: String
    ) throws -> String {
        switch source {
        case .localPath(let path):
            return path
        case .gitURL(let url):
            let destination = URL(fileURLWithPath: temporaryRoot)
                .appendingPathComponent(UUID().uuidString)
                .path
            try FileManager.default.createDirectory(
                at: URL(fileURLWithPath: temporaryRoot),
                withIntermediateDirectories: true,
                attributes: nil
            )

            let process = Process()
            process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
            process.arguments = ["git", "clone", "--depth", "1", url, destination]
            let pipe = Pipe()
            process.standardOutput = pipe
            process.standardError = pipe
            do {
                try process.run()
            } catch {
                throw PluginError.commandFailed("Failed to clone plugin source `\(url)`: \(error.localizedDescription)")
            }
            process.waitUntilExit()
            guard process.terminationStatus == 0 else {
                let output = String(
                    data: pipe.fileHandleForReading.readDataToEndOfFile(),
                    encoding: .utf8
                )?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
                throw PluginError.commandFailed("Failed to clone plugin source `\(url)`: \(output)")
            }
            return destination
        }
    }

    private func cleanupTemporarySourceIfNeeded(
        _ path: String,
        source: PluginInstallSource
    ) {
        guard case .gitURL = source else {
            return
        }
        try? FileManager.default.removeItem(atPath: path)
    }

    private func temporaryInstallRoot() -> String {
        URL(fileURLWithPath: installRootPath())
            .appendingPathComponent(".tmp")
            .path
    }

    private func discoverPluginDirs(at rootPath: String) throws -> [String] {
        guard FileManager.default.fileExists(atPath: rootPath) else {
            return []
        }

        if (try? Self.pluginManifestPath(rootPath: rootPath)) != nil {
            return [rootPath]
        }

        let entries = try FileManager.default.contentsOfDirectory(
            at: URL(fileURLWithPath: rootPath),
            includingPropertiesForKeys: [.isDirectoryKey],
            options: [.skipsHiddenFiles]
        )

        return entries.compactMap { entry in
            guard (try? entry.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true else {
                return nil
            }
            let path = entry.path
            return (try? Self.pluginManifestPath(rootPath: path)) != nil ? path : nil
        }
    }

    private func copyDirectory(from sourcePath: String, to destinationPath: String) throws {
        let destinationURL = URL(fileURLWithPath: destinationPath)
        try FileManager.default.createDirectory(
            at: destinationURL.deletingLastPathComponent(),
            withIntermediateDirectories: true,
            attributes: nil
        )
        try FileManager.default.copyItem(
            at: URL(fileURLWithPath: sourcePath),
            to: destinationURL
        )
    }

    private func removeItemIfExists(atPath path: String) throws {
        guard FileManager.default.fileExists(atPath: path) else {
            return
        }
        try FileManager.default.removeItem(atPath: path)
    }

    private static func unixTimeMilliseconds() -> Int64 {
        Int64(Date().timeIntervalSince1970 * 1000)
    }

    private static func sanitizePluginID(_ pluginID: String) -> String {
        pluginID.replacingOccurrences(of: "[^A-Za-z0-9._-]", with: "_", options: .regularExpression)
    }

    private static func standardizePath(_ path: String) -> String {
        (path as NSString).standardizingPath
    }

    private static func detectClawCodeManifestContractGaps(
        _ root: [String: Any]
    ) -> [PluginManifestValidationError] {
        var errors: [PluginManifestValidationError] = []

        let unsupportedFields: [(String, String)] = [
            (
                "skills",
                "plugin manifest field `skills` uses the Claude Code plugin contract; SwiftAgent follows `claw-code` and discovers skills from local roots such as `.claw/skills`, `.omc/skills`, `.agents/skills`, `.codex/skills`, and `.claude/skills`."
            ),
            (
                "mcpServers",
                "plugin manifest field `mcpServers` uses the Claude Code plugin contract; SwiftAgent does not import MCP servers from plugin manifests."
            ),
            (
                "agents",
                "plugin manifest field `agents` uses the Claude Code plugin contract; SwiftAgent does not load plugin-managed agent catalogs from plugin manifests."
            ),
        ]

        for (field, detail) in unsupportedFields where root[field] != nil {
            errors.append(.unsupportedManifestContract(detail: detail))
        }

        if let commands = root["commands"] as? [Any],
           commands.contains(where: { $0 is String }) {
            errors.append(
                .unsupportedManifestContract(
                    detail: "plugin manifest field `commands` uses Claude Code-style directory globs; SwiftAgent follows `claw-code` and does not load plugin slash-command markdown catalogs from plugin manifests."
                )
            )
        }

        if let hooks = root["hooks"] as? [String: Any] {
            let supportedHooks: Set<String> = ["PreToolUse", "PostToolUse", "PostToolUseFailure"]
            for hookName in hooks.keys where !supportedHooks.contains(hookName) {
                errors.append(
                    .unsupportedManifestContract(
                        detail: "plugin hook `\(hookName)` uses the Claude Code lifecycle contract; SwiftAgent currently supports only PreToolUse, PostToolUse, and PostToolUseFailure."
                    )
                )
            }
        }

        return errors
    }

    private static func buildPluginManifest(
        rootPath: String,
        raw: RawPluginManifest
    ) throws -> PluginManifest {
        var errors: [PluginManifestValidationError] = []

        validateRequiredField("name", raw.name, errors: &errors)
        validateRequiredField("version", raw.version, errors: &errors)
        validateRequiredField("description", raw.description, errors: &errors)

        let permissions = buildPermissions(raw.permissions, errors: &errors)
        validateCommandEntries(rootPath: rootPath, entries: raw.hooks.preToolUse, kind: "hook", errors: &errors)
        validateCommandEntries(rootPath: rootPath, entries: raw.hooks.postToolUse, kind: "hook", errors: &errors)
        validateCommandEntries(rootPath: rootPath, entries: raw.hooks.postToolUseFailure, kind: "hook", errors: &errors)
        validateCommandEntries(rootPath: rootPath, entries: raw.lifecycle.initialize, kind: "lifecycle command", errors: &errors)
        validateCommandEntries(rootPath: rootPath, entries: raw.lifecycle.shutdown, kind: "lifecycle command", errors: &errors)
        let tools = buildTools(rootPath: rootPath, tools: raw.tools, errors: &errors)
        let commands = buildCommands(rootPath: rootPath, commands: raw.commands, errors: &errors)

        if !errors.isEmpty {
            throw PluginError.manifestValidation(errors)
        }

        return PluginManifest(
            name: raw.name,
            version: raw.version,
            description: raw.description,
            permissions: permissions,
            defaultEnabled: raw.defaultEnabled,
            hooks: raw.hooks,
            lifecycle: raw.lifecycle,
            tools: tools,
            commands: commands
        )
    }

    private static func buildPermissions(
        _ permissions: [String],
        errors: inout [PluginManifestValidationError]
    ) -> [PluginPermission] {
        var seen = Set<String>()
        var result: [PluginPermission] = []

        for permission in permissions {
            let trimmed = permission.trimmingCharacters(in: .whitespacesAndNewlines)
            if trimmed.isEmpty {
                errors.append(.emptyEntryField(kind: "permission", field: "value", name: nil))
                continue
            }
            if !seen.insert(trimmed).inserted {
                errors.append(.duplicatePermission(permission: trimmed))
                continue
            }
            guard let parsed = PluginPermission(rawValue: trimmed) else {
                errors.append(.invalidPermission(permission: trimmed))
                continue
            }
            result.append(parsed)
        }

        return result
    }

    private static func buildTools(
        rootPath: String,
        tools: [RawPluginToolManifest],
        errors: inout [PluginManifestValidationError]
    ) -> [PluginToolManifest] {
        var seen = Set<String>()
        var result: [PluginToolManifest] = []

        for tool in tools {
            let name = tool.name.trimmingCharacters(in: .whitespacesAndNewlines)
            if name.isEmpty {
                errors.append(.emptyEntryField(kind: "tool", field: "name", name: nil))
                continue
            }
            if !seen.insert(name).inserted {
                errors.append(.duplicateEntry(kind: "tool", name: name))
                continue
            }
            if tool.description.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                errors.append(.emptyEntryField(kind: "tool", field: "description", name: name))
            }
            if tool.command.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                errors.append(.emptyEntryField(kind: "tool", field: "command", name: name))
            } else {
                validateCommandEntry(rootPath: rootPath, entry: tool.command, kind: "tool", errors: &errors)
            }
            guard tool.inputSchema.objectValue != nil else {
                errors.append(.invalidToolInputSchema(toolName: name))
                continue
            }
            guard let requiredPermission = PluginToolPermission(rawValue: tool.requiredPermission.trimmingCharacters(in: .whitespacesAndNewlines)) else {
                errors.append(
                    .invalidToolRequiredPermission(
                        toolName: name,
                        permission: tool.requiredPermission.trimmingCharacters(in: .whitespacesAndNewlines)
                    )
                )
                continue
            }

            result.append(
                PluginToolManifest(
                    name: name,
                    description: tool.description,
                    inputSchema: tool.inputSchema,
                    command: tool.command,
                    args: tool.args,
                    requiredPermission: requiredPermission
                )
            )
        }

        return result
    }

    private static func buildCommands(
        rootPath: String,
        commands: [PluginCommandManifest],
        errors: inout [PluginManifestValidationError]
    ) -> [PluginCommandManifest] {
        var seen = Set<String>()
        var result: [PluginCommandManifest] = []

        for command in commands {
            let name = command.name.trimmingCharacters(in: .whitespacesAndNewlines)
            if name.isEmpty {
                errors.append(.emptyEntryField(kind: "command", field: "name", name: nil))
                continue
            }
            if !seen.insert(name).inserted {
                errors.append(.duplicateEntry(kind: "command", name: name))
                continue
            }
            if command.description.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                errors.append(.emptyEntryField(kind: "command", field: "description", name: name))
            }
            if command.command.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                errors.append(.emptyEntryField(kind: "command", field: "command", name: name))
            } else {
                validateCommandEntry(rootPath: rootPath, entry: command.command, kind: "command", errors: &errors)
            }
            result.append(command)
        }

        return result
    }

    private static func validateRequiredField(
        _ field: String,
        _ value: String,
        errors: inout [PluginManifestValidationError]
    ) {
        if value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            errors.append(.emptyField(field: field))
        }
    }

    private static func validateCommandEntries(
        rootPath: String,
        entries: [String],
        kind: String,
        errors: inout [PluginManifestValidationError]
    ) {
        for entry in entries {
            validateCommandEntry(rootPath: rootPath, entry: entry, kind: kind, errors: &errors)
        }
    }

    private static func validateCommandEntry(
        rootPath: String,
        entry: String,
        kind: String,
        errors: inout [PluginManifestValidationError]
    ) {
        if entry.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            errors.append(.emptyEntryField(kind: kind, field: "command", name: nil))
            return
        }
        if isLiteralCommand(entry) {
            return
        }

        let path = resolvePath(rootPath: rootPath, entry: entry)
        var isDirectory: ObjCBool = false
        guard FileManager.default.fileExists(atPath: path, isDirectory: &isDirectory) else {
            errors.append(.missingPath(kind: kind, path: path))
            return
        }
        if isDirectory.boolValue {
            errors.append(.pathIsDirectory(kind: kind, path: path))
        }
    }

    private static func resolve(
        entries hooks: PluginHooks,
        relativeTo rootPath: String
    ) -> PluginHooks {
        PluginHooks(
            preToolUse: hooks.preToolUse.map { resolvePath(rootPath: rootPath, entry: $0) },
            postToolUse: hooks.postToolUse.map { resolvePath(rootPath: rootPath, entry: $0) },
            postToolUseFailure: hooks.postToolUseFailure.map { resolvePath(rootPath: rootPath, entry: $0) }
        )
    }

    private static func resolve(
        entries lifecycle: PluginLifecycle,
        relativeTo rootPath: String
    ) -> PluginLifecycle {
        PluginLifecycle(
            initialize: lifecycle.initialize.map { resolvePath(rootPath: rootPath, entry: $0) },
            shutdown: lifecycle.shutdown.map { resolvePath(rootPath: rootPath, entry: $0) }
        )
    }

    private static func resolve(
        manifests: [PluginToolManifest],
        pluginID: String,
        pluginName: String,
        rootPath: String
    ) -> [PluginTool] {
        manifests.map { manifest in
            PluginTool(
                pluginID: pluginID,
                pluginName: pluginName,
                definition: PluginToolDefinition(
                    name: manifest.name,
                    description: manifest.description,
                    inputSchema: manifest.inputSchema
                ),
                command: resolvePath(rootPath: rootPath, entry: manifest.command),
                args: manifest.args,
                requiredPermission: manifest.requiredPermission,
                rootPath: rootPath
            )
        }
    }

    private static func pluginManifestPath(rootPath: String) throws -> String {
        let direct = URL(fileURLWithPath: rootPath).appendingPathComponent(manifestFileName).path
        if FileManager.default.fileExists(atPath: direct) {
            return direct
        }

        let packaged = URL(fileURLWithPath: rootPath).appendingPathComponent(manifestRelativePath).path
        if FileManager.default.fileExists(atPath: packaged) {
            return packaged
        }

        throw PluginError.notFound(
            "plugin manifest not found at \(direct) or \(packaged)"
        )
    }

    private static func pluginIdentifier(name: String, marketplace: String) -> String {
        "\(name)@\(marketplace)"
    }

    private static func resolvePath(rootPath: String, entry: String) -> String {
        if isLiteralCommand(entry) || entry.hasPrefix("/") {
            return entry
        }

        return URL(fileURLWithPath: rootPath)
            .appendingPathComponent(entry)
            .standardizedFileURL.path
    }

    private static func isLiteralCommand(_ entry: String) -> Bool {
        !entry.hasPrefix("./") && !entry.hasPrefix("../") && !entry.hasPrefix("/")
    }

    private static func expandPath(_ path: String) -> String {
        let expanded = (path as NSString).expandingTildeInPath
        return (expanded as NSString).standardizingPath
    }
}

private struct PluginDiscovery {
    var plugins: [PluginDefinition] = []
    var failures: [PluginLoadFailure] = []

    mutating func merge(_ other: PluginDiscovery) {
        plugins.append(contentsOf: other.plugins)
        failures.append(contentsOf: other.failures)
    }
}

private struct RawPluginManifest: Decodable {
    let name: String
    let version: String
    let description: String
    let permissions: [String]
    let defaultEnabled: Bool
    let hooks: PluginHooks
    let lifecycle: PluginLifecycle
    let tools: [RawPluginToolManifest]
    let commands: [PluginCommandManifest]

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.name = try container.decodeIfPresent(String.self, forKey: .name) ?? ""
        self.version = try container.decodeIfPresent(String.self, forKey: .version) ?? ""
        self.description = try container.decodeIfPresent(String.self, forKey: .description) ?? ""
        self.permissions = try container.decodeIfPresent([String].self, forKey: .permissions) ?? []
        self.defaultEnabled = try container.decodeIfPresent(Bool.self, forKey: .defaultEnabled) ?? false
        self.hooks = try container.decodeIfPresent(PluginHooks.self, forKey: .hooks) ?? PluginHooks()
        self.lifecycle = try container.decodeIfPresent(PluginLifecycle.self, forKey: .lifecycle) ?? PluginLifecycle()
        self.tools = try container.decodeIfPresent([RawPluginToolManifest].self, forKey: .tools) ?? []
        self.commands = try container.decodeIfPresent([PluginCommandManifest].self, forKey: .commands) ?? []
    }

    private enum CodingKeys: String, CodingKey {
        case name
        case version
        case description
        case permissions
        case defaultEnabled
        case hooks
        case lifecycle
        case tools
        case commands
    }
}

private struct RawPluginToolManifest: Decodable {
    let name: String
    let description: String
    let inputSchema: PluginJSONValue
    let command: String
    let args: [String]
    let requiredPermission: String

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.name = try container.decodeIfPresent(String.self, forKey: .name) ?? ""
        self.description = try container.decodeIfPresent(String.self, forKey: .description) ?? ""
        self.inputSchema = try container.decodeIfPresent(PluginJSONValue.self, forKey: .inputSchema) ?? .object([:])
        self.command = try container.decodeIfPresent(String.self, forKey: .command) ?? ""
        self.args = try container.decodeIfPresent([String].self, forKey: .args) ?? []
        self.requiredPermission = try container.decodeIfPresent(String.self, forKey: .requiredPermission) ?? PluginToolPermission.dangerFullAccess.rawValue
    }

    private enum CodingKeys: String, CodingKey {
        case name
        case description
        case inputSchema
        case command
        case args
        case requiredPermission
    }
}
