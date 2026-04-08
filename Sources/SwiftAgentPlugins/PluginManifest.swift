//
//  PluginManifest.swift
//  SwiftAgent
//
//  Created by SwiftAgent on 2026/04/08.
//

import Foundation

/// A validated plugin manifest compatible with `claw-code`.
public struct PluginManifest: Sendable, Codable, Equatable {
    public let name: String
    public let version: String
    public let description: String
    public let permissions: [PluginPermission]
    public let defaultEnabled: Bool
    public let hooks: PluginHooks
    public let lifecycle: PluginLifecycle
    public let tools: [PluginToolManifest]
    public let commands: [PluginCommandManifest]

    public init(
        name: String,
        version: String,
        description: String,
        permissions: [PluginPermission],
        defaultEnabled: Bool,
        hooks: PluginHooks,
        lifecycle: PluginLifecycle,
        tools: [PluginToolManifest],
        commands: [PluginCommandManifest]
    ) {
        self.name = name
        self.version = version
        self.description = description
        self.permissions = permissions
        self.defaultEnabled = defaultEnabled
        self.hooks = hooks
        self.lifecycle = lifecycle
        self.tools = tools
        self.commands = commands
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

/// A validated tool entry within a plugin manifest.
public struct PluginToolManifest: Sendable, Codable, Equatable {
    public let name: String
    public let description: String
    public let inputSchema: PluginJSONValue
    public let command: String
    public let args: [String]
    public let requiredPermission: PluginToolPermission

    public init(
        name: String,
        description: String,
        inputSchema: PluginJSONValue,
        command: String,
        args: [String] = [],
        requiredPermission: PluginToolPermission
    ) {
        self.name = name
        self.description = description
        self.inputSchema = inputSchema
        self.command = command
        self.args = args
        self.requiredPermission = requiredPermission
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

/// A validated slash-command style entry within a plugin manifest.
public struct PluginCommandManifest: Sendable, Codable, Equatable {
    public let name: String
    public let description: String
    public let command: String

    public init(
        name: String,
        description: String,
        command: String
    ) {
        self.name = name
        self.description = description
        self.command = command
    }
}
