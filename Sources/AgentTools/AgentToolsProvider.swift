//
//  AgentToolsProvider.swift
//  AgentTools
//
//  Created by SwiftAgent on 2025/01/15.
//

import Foundation
import SwiftAgent
import OpenFoundationModels

/// A tool provider that creates AgentTools instances.
///
/// `AgentToolsProvider` is the default implementation of `ToolProvider`
/// that creates actual tool instances from the AgentTools module.
///
/// ## Usage
///
/// ```swift
/// let provider = AgentToolsProvider(workingDirectory: "/path/to/work")
///
/// // Get all default tools
/// let tools = provider.tools(for: ToolConfiguration.ToolPreset.default.toolNames)
///
/// // Get a specific tool
/// if let readTool = provider.tool(named: "file_read") {
///     // Use the tool
/// }
/// ```
public struct AgentToolsProvider: ToolProvider {

    /// The working directory for file operations.
    public let workingDirectory: String

    /// Creates a new AgentTools provider.
    ///
    /// - Parameter workingDirectory: The working directory for file operations.
    public init(workingDirectory: String = FileManager.default.currentDirectoryPath) {
        self.workingDirectory = workingDirectory
    }

    // MARK: - ToolProvider

    public func tools(for names: [String]) -> [any Tool] {
        return names.compactMap { tool(named: $0) }
    }

    public func tool(named name: String) -> (any Tool)? {
        switch name {
        case ReadTool.name:
            return ReadTool(workingDirectory: workingDirectory)

        case WriteTool.name:
            return WriteTool(workingDirectory: workingDirectory)

        case EditTool.name:
            return EditTool(workingDirectory: workingDirectory)

        case MultiEditTool.name:
            return MultiEditTool(workingDirectory: workingDirectory)

        case GrepTool.name:
            return GrepTool(workingDirectory: workingDirectory)

        case GlobTool.name:
            return GlobTool(workingDirectory: workingDirectory)

        case ExecuteCommandTool.name:
            return ExecuteCommandTool()

        case GitTool.name:
            return GitTool()

        case URLFetchTool.name:
            return URLFetchTool()

        default:
            return nil
        }
    }

    // MARK: - Convenience Methods

    /// Returns all available tools.
    public func allTools() -> [any Tool] {
        return tools(for: Self.allToolNames)
    }

    /// All tool names available in AgentTools.
    public static let allToolNames: [String] = [
        ReadTool.name,
        WriteTool.name,
        EditTool.name,
        MultiEditTool.name,
        GrepTool.name,
        GlobTool.name,
        ExecuteCommandTool.name,
        GitTool.name,
        URLFetchTool.name
    ]
}

// MARK: - DefaultToolProvider Extension

extension DefaultToolProvider {

    /// Creates a DefaultToolProvider backed by AgentToolsProvider.
    ///
    /// This is a convenience factory for creating a fully functional tool provider.
    ///
    /// - Parameter workingDirectory: The working directory for file operations.
    /// - Returns: A DefaultToolProvider that uses AgentToolsProvider for tool creation.
    public static func withAgentTools(
        workingDirectory: String = FileManager.default.currentDirectoryPath
    ) -> DefaultToolProvider {
        let agentToolsProvider = AgentToolsProvider(workingDirectory: workingDirectory)
        return DefaultToolProvider(
            workingDirectory: workingDirectory,
            toolFactory: { name, _ in
                agentToolsProvider.tool(named: name)
            }
        )
    }
}
