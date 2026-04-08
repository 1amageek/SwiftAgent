//
//  PluginRegistry.swift
//  SwiftAgent
//
//  Created by SwiftAgent on 2026/04/08.
//

import Foundation
import SwiftAgent

/// A registered plugin together with its enabled state.
public struct RegisteredPlugin: Sendable, Equatable {
    public let definition: PluginDefinition
    public let enabled: Bool

    public init(definition: PluginDefinition, enabled: Bool) {
        self.definition = definition
        self.enabled = enabled
    }

    public var metadata: PluginMetadata {
        definition.metadata
    }
}

/// A stable listing summary for a registered plugin.
public struct PluginSummary: Sendable, Equatable {
    public let metadata: PluginMetadata
    public let enabled: Bool

    public init(metadata: PluginMetadata, enabled: Bool) {
        self.metadata = metadata
        self.enabled = enabled
    }
}

/// A non-fatal plugin load failure captured during discovery.
public struct PluginLoadFailure: Sendable, Equatable, CustomStringConvertible {
    public let pluginRoot: String
    public let kind: PluginKind
    public let source: String
    public let message: String

    public init(
        pluginRoot: String,
        kind: PluginKind,
        source: String,
        message: String
    ) {
        self.pluginRoot = pluginRoot
        self.kind = kind
        self.source = source
        self.message = message
    }

    public var description: String {
        "failed to load \(kind.rawValue) plugin from `\(pluginRoot)` (source: \(source)): \(message)"
    }
}

/// The result of a plugin discovery pass.
public struct PluginRegistryReport: Sendable {
    public let registry: PluginRegistry
    public let failures: [PluginLoadFailure]

    public init(registry: PluginRegistry, failures: [PluginLoadFailure]) {
        self.registry = registry
        self.failures = failures
    }

    public var hasFailures: Bool {
        !failures.isEmpty
    }

    public func intoRegistry() throws -> PluginRegistry {
        if failures.isEmpty {
            return registry
        }
        throw PluginError.loadFailures(failures)
    }
}

/// In-memory registry of loaded plugins.
public struct PluginRegistry: Sendable, Equatable {
    public let plugins: [RegisteredPlugin]

    public init(plugins: [RegisteredPlugin] = []) {
        self.plugins = plugins
    }

    public func register(
        _ definition: PluginDefinition,
        enabled: Bool
    ) -> PluginRegistry {
        PluginRegistry(plugins: plugins + [RegisteredPlugin(definition: definition, enabled: enabled)])
    }

    public func summaries() -> [PluginSummary] {
        plugins.map { PluginSummary(metadata: $0.metadata, enabled: $0.enabled) }
    }

    public func contains(_ pluginID: String) -> Bool {
        plugins.contains { $0.metadata.id == pluginID }
    }

    public func aggregatedHooks() throws -> PluginHooks {
        try plugins
            .filter(\.enabled)
            .reduce(into: PluginHooks()) { hooks, plugin in
                try plugin.definition.validate()
                hooks = hooks.merged(with: plugin.definition.hooks)
            }
    }

    public func aggregatedTools() throws -> [PluginTool] {
        var tools: [PluginTool] = []
        var seenNames: [String: String] = [:]

        for plugin in plugins where plugin.enabled {
            try plugin.definition.validate()

            for tool in plugin.definition.tools {
                if let existing = seenNames.updateValue(tool.pluginID, forKey: tool.definition.name) {
                    throw PluginError.invalidManifest(
                        "plugin tool `\(tool.definition.name)` is defined by both `\(existing)` and `\(tool.pluginID)`"
                    )
                }
                tools.append(tool)
            }
        }

        return tools
    }

    public func aggregatedSwiftAgentTools() throws -> [any Tool] {
        try aggregatedTools().swiftAgentTools()
    }

    public func initialize() throws {
        for plugin in plugins where plugin.enabled {
            try plugin.definition.validate()
            try plugin.definition.initialize()
        }
    }

    public func shutdown() throws {
        for plugin in plugins.reversed() where plugin.enabled {
            try plugin.definition.shutdown()
        }
    }
}
