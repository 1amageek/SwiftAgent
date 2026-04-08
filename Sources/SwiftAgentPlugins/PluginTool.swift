//
//  PluginTool.swift
//  SwiftAgent
//
//  Created by SwiftAgent on 2026/04/08.
//

import Foundation
import SwiftAgent

/// A plugin-native executable tool definition.
public struct PluginTool: Sendable, Equatable {
    public let pluginID: String
    public let pluginName: String
    public let definition: PluginToolDefinition
    public let command: String
    public let args: [String]
    public let requiredPermission: PluginToolPermission
    public let rootPath: String?

    public init(
        pluginID: String,
        pluginName: String,
        definition: PluginToolDefinition,
        command: String,
        args: [String],
        requiredPermission: PluginToolPermission,
        rootPath: String?
    ) {
        self.pluginID = pluginID
        self.pluginName = pluginName
        self.definition = definition
        self.command = command
        self.args = args
        self.requiredPermission = requiredPermission
        self.rootPath = rootPath
    }

    public func execute(argumentsJSON: String) async throws -> String {
        try Task.checkCancellation()
        try TurnCancellationContext.current?.checkCancellation()

        let process = Process()
        let stdoutPipe = Pipe()
        let stderrPipe = Pipe()
        let stdinPipe = Pipe()

        let execution = try resolvedExecution()
        process.executableURL = URL(fileURLWithPath: execution.executable)
        process.arguments = execution.arguments
        process.standardInput = stdinPipe
        process.standardOutput = stdoutPipe
        process.standardError = stderrPipe

        var environment = ProcessInfo.processInfo.environment
        environment["CLAWD_PLUGIN_ID"] = pluginID
        environment["CLAWD_PLUGIN_NAME"] = pluginName
        environment["CLAWD_TOOL_NAME"] = definition.name
        environment["CLAWD_TOOL_INPUT"] = argumentsJSON
        if let rootPath {
            environment["CLAWD_PLUGIN_ROOT"] = rootPath
            process.currentDirectoryURL = URL(fileURLWithPath: rootPath)
        }
        process.environment = environment

        do {
            try process.run()
        } catch {
            throw PluginError.commandFailed(
                "Failed to launch plugin tool `\(definition.name)` from `\(pluginID)`: \(error.localizedDescription)"
            )
        }

        if let data = argumentsJSON.data(using: .utf8) {
            stdinPipe.fileHandleForWriting.write(data)
        }
        stdinPipe.fileHandleForWriting.closeFile()

        process.waitUntilExit()

        try Task.checkCancellation()
        try TurnCancellationContext.current?.checkCancellation()

        let stdoutData = stdoutPipe.fileHandleForReading.readDataToEndOfFile()
        let stderrData = stderrPipe.fileHandleForReading.readDataToEndOfFile()

        let stdout = String(data: stdoutData, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let stderr = String(data: stderrData, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""

        guard process.terminationStatus == 0 else {
            let detail = stderr.isEmpty ? "exit status \(process.terminationStatus)" : stderr
            throw PluginError.commandFailed(
                "plugin tool `\(definition.name)` from `\(pluginID)` failed for `\(command)`: \(detail)"
            )
        }

        return stdout
    }

    public func makeSwiftAgentTool() throws -> PluginToolAdapter {
        try PluginToolAdapter(pluginTool: self)
    }

    private func resolvedExecution() throws -> (executable: String, arguments: [String]) {
        if command.hasPrefix("/") {
            return (command, args)
        }

        return ("/usr/bin/env", [command] + args)
    }
}

extension Sequence where Element == PluginTool {
    /// Bridges plugin-native tools into SwiftAgent's `Tool` runtime.
    public func swiftAgentTools() throws -> [any Tool] {
        try map { try $0.makeSwiftAgentTool() as any Tool }
    }
}
