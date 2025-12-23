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

    /// Optional web search provider for WebSearchTool.
    private let searchProvider: WebSearchProvider?

    /// Creates a new AgentTools provider.
    ///
    /// - Parameters:
    ///   - workingDirectory: The working directory for file operations.
    ///   - searchProvider: Optional search provider for web search functionality.
    public init(
        workingDirectory: String = FileManager.default.currentDirectoryPath,
        searchProvider: WebSearchProvider? = nil
    ) {
        self.workingDirectory = workingDirectory
        self.searchProvider = searchProvider
    }

    // MARK: - ToolProvider

    public func tools(for names: [String]) -> [any Tool] {
        return names.compactMap { tool(named: $0) }
    }

    public func tool(named name: String) -> (any Tool)? {
        switch name {
        case "read":
            return ReadTool(workingDirectory: workingDirectory)

        case "write":
            return WriteTool(workingDirectory: workingDirectory)

        case "edit":
            return EditTool(workingDirectory: workingDirectory)

        case "multi_edit":
            return MultiEditTool(workingDirectory: workingDirectory)

        case "grep":
            return GrepTool(workingDirectory: workingDirectory)

        case "glob":
            return GlobTool(workingDirectory: workingDirectory)

        case "bash":
            return ExecuteCommandTool(workingDirectory: workingDirectory)

        case "git":
            return GitTool()

        case "url_fetch":
            return URLFetchTool()

        case "web_search":
            if let provider = searchProvider {
                return WebSearchTool(provider: provider)
            }
            // Return mock provider for testing if no provider configured
            return WebSearchTool(provider: MockSearchProvider())

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
        "read",       // ReadTool
        "write",      // WriteTool
        "edit",       // EditTool
        "multi_edit", // MultiEditTool
        "grep",       // GrepTool
        "glob",       // GlobTool
        "bash",       // ExecuteCommandTool
        "git",        // GitTool
        "url_fetch",  // URLFetchTool
        "web_search"  // WebSearchTool
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
