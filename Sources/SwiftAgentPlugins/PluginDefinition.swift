//
//  PluginDefinition.swift
//  SwiftAgent
//
//  Created by SwiftAgent on 2026/04/08.
//

import Foundation

/// A fully loaded runtime plugin definition.
public struct PluginDefinition: Sendable, Equatable {
    public let metadata: PluginMetadata
    public let hooks: PluginHooks
    public let lifecycle: PluginLifecycle
    public let tools: [PluginTool]

    public init(
        metadata: PluginMetadata,
        hooks: PluginHooks,
        lifecycle: PluginLifecycle,
        tools: [PluginTool]
    ) {
        self.metadata = metadata
        self.hooks = hooks
        self.lifecycle = lifecycle
        self.tools = tools
    }

    public func validate() throws {
        try validateCommandEntries(hooks.preToolUse, kind: "hook")
        try validateCommandEntries(hooks.postToolUse, kind: "hook")
        try validateCommandEntries(hooks.postToolUseFailure, kind: "hook")
        try validateCommandEntries(lifecycle.initialize, kind: "lifecycle command")
        try validateCommandEntries(lifecycle.shutdown, kind: "lifecycle command")
        try validateCommandEntries(tools.map(\.command), kind: "tool")
    }

    public func initialize() throws {
        try runLifecycleCommands(phase: "init", commands: lifecycle.initialize)
    }

    public func shutdown() throws {
        try runLifecycleCommands(phase: "shutdown", commands: lifecycle.shutdown)
    }

    private func validateCommandEntries(_ entries: [String], kind: String) throws {
        for entry in entries {
            try validateCommandPath(entry, kind: kind)
        }
    }

    private func validateCommandPath(_ entry: String, kind: String) throws {
        if Self.isLiteralCommand(entry) {
            return
        }

        let path = entry.hasPrefix("/") ? entry : resolvedPath(for: entry)
        var isDirectory: ObjCBool = false
        guard FileManager.default.fileExists(atPath: path, isDirectory: &isDirectory) else {
            throw PluginError.invalidManifest("\(kind) path `\(path)` does not exist")
        }
        guard !isDirectory.boolValue else {
            throw PluginError.invalidManifest("\(kind) path `\(path)` must point to a file")
        }
    }

    private func runLifecycleCommands(
        phase: String,
        commands: [String]
    ) throws {
        guard !lifecycle.isEmpty, !commands.isEmpty else {
            return
        }

        for command in commands {
            let process = Process()

            if Self.isLiteralCommand(command) {
                process.executableURL = URL(fileURLWithPath: "/bin/sh")
                process.arguments = ["-lc", command]
            } else {
                let path = resolvedPath(for: command)
                process.executableURL = URL(fileURLWithPath: "/bin/sh")
                process.arguments = [path]
            }

            if let rootPath = metadata.rootPath {
                process.currentDirectoryURL = URL(fileURLWithPath: rootPath)
            }

            let outputPipe = Pipe()
            process.standardOutput = outputPipe
            process.standardError = outputPipe

            do {
                try process.run()
            } catch {
                throw PluginError.commandFailed(
                    "plugin `\(metadata.id)` \(phase) failed for `\(command)`: \(error.localizedDescription)"
                )
            }

            process.waitUntilExit()

            guard process.terminationStatus == 0 else {
                let data = outputPipe.fileHandleForReading.readDataToEndOfFile()
                let stderr = String(data: data, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
                let detail = stderr.isEmpty ? "exit status \(process.terminationStatus)" : stderr
                throw PluginError.commandFailed(
                    "plugin `\(metadata.id)` \(phase) failed for `\(command)`: \(detail)"
                )
            }
        }
    }

    private func resolvedPath(for entry: String) -> String {
        guard let rootPath = metadata.rootPath else {
            return entry
        }
        return URL(fileURLWithPath: rootPath)
            .appendingPathComponent(entry)
            .standardizedFileURL.path
    }

    private static func isLiteralCommand(_ entry: String) -> Bool {
        !entry.hasPrefix("./") && !entry.hasPrefix("../") && !entry.hasPrefix("/")
    }
}
