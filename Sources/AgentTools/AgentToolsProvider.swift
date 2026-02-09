//
//  AgentToolsProvider.swift
//  AgentTools
//
//  Created by SwiftAgent on 2025/01/15.
//

import Foundation
import SwiftAgent

#if OpenFoundationModels
import OpenFoundationModels
#endif

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
/// if let readTool = provider.tool(named: "Read") {
///     // Use the tool
/// }
/// ```
///
/// ## Security
///
/// Security policies (permissions and sandboxing) are enforced at the
/// middleware layer, not in the tool provider. Use `AgentConfiguration.withSecurity()`
/// to configure security policies.
public struct AgentToolsProvider: ToolProvider {

    /// The working directory for file operations.
    public let workingDirectory: String

    /// Optional web search provider for WebSearchTool.
    private let searchProvider: WebSearchProvider?

    /// Shared notebook storage instance.
    private let notebookStorage: NotebookStorage

    #if OpenFoundationModels
    /// Language model for DispatchTool.
    private let languageModel: (any LanguageModel)?

    /// Creates a new AgentTools provider.
    ///
    /// - Parameters:
    ///   - workingDirectory: The working directory for file operations.
    ///   - searchProvider: Optional search provider for web search functionality.
    ///   - notebookStorage: Shared notebook storage instance. Defaults to a new instance.
    ///   - languageModel: Language model for DispatchTool. If `nil`, Dispatch tool is not available.
    public init(
        workingDirectory: String = FileManager.default.currentDirectoryPath,
        searchProvider: WebSearchProvider? = nil,
        notebookStorage: NotebookStorage = NotebookStorage(),
        languageModel: (any LanguageModel)? = nil
    ) {
        self.workingDirectory = workingDirectory
        self.searchProvider = searchProvider
        self.notebookStorage = notebookStorage
        self.languageModel = languageModel
    }
    #else
    /// Creates a new AgentTools provider.
    ///
    /// - Parameters:
    ///   - workingDirectory: The working directory for file operations.
    ///   - searchProvider: Optional search provider for web search functionality.
    ///   - notebookStorage: Shared notebook storage instance. Defaults to a new instance.
    public init(
        workingDirectory: String = FileManager.default.currentDirectoryPath,
        searchProvider: WebSearchProvider? = nil,
        notebookStorage: NotebookStorage = NotebookStorage()
    ) {
        self.workingDirectory = workingDirectory
        self.searchProvider = searchProvider
        self.notebookStorage = notebookStorage
    }
    #endif

    // MARK: - ToolProvider

    public func tools(for names: [String]) -> [any Tool] {
        return names.compactMap { tool(named: $0) }
    }

    public func tool(named name: String) -> (any Tool)? {
        switch name {
        case "Read":
            return ReadTool(workingDirectory: workingDirectory)

        case "Write":
            return WriteTool(workingDirectory: workingDirectory)

        case "Edit":
            return EditTool(workingDirectory: workingDirectory)

        case "MultiEdit":
            return MultiEditTool(workingDirectory: workingDirectory)

        case "Grep":
            return GrepTool(workingDirectory: workingDirectory)

        case "Glob":
            return GlobTool(workingDirectory: workingDirectory)

        case "Bash":
            return ExecuteCommandTool(workingDirectory: workingDirectory)

        case "Git":
            return GitTool()

        case "WebFetch":
            return URLFetchTool()

        case "WebSearch":
            if let provider = searchProvider {
                return WebSearchTool(provider: provider)
            }
            // Return mock provider for testing if no provider configured
            return WebSearchTool(provider: MockSearchProvider())

        case "Notebook":
            return NotebookTool(storage: notebookStorage)

        case "Dispatch":
            #if OpenFoundationModels
            if let model = languageModel {
                return DispatchTool(
                    languageModel: model,
                    notebookStorage: notebookStorage
                )
            }
            return nil
            #else
            return DispatchTool(notebookStorage: notebookStorage)
            #endif

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
        "Read",       // ReadTool
        "Write",      // WriteTool
        "Edit",       // EditTool
        "MultiEdit",  // MultiEditTool
        "Grep",       // GrepTool
        "Glob",       // GlobTool
        "Bash",       // ExecuteCommandTool
        "Git",        // GitTool
        "WebFetch",   // URLFetchTool
        "WebSearch",  // WebSearchTool
        "Notebook",   // NotebookTool
        "Dispatch"    // DispatchTool
    ]
}

// MARK: - DefaultToolProvider Extension

extension DefaultToolProvider {

    /// Creates a DefaultToolProvider backed by AgentToolsProvider.
    ///
    /// This is a convenience factory for creating a fully functional tool provider.
    ///
    /// ## Security
    ///
    /// Security policies (permissions and sandboxing) are enforced at the
    /// middleware layer via `AgentConfiguration.withSecurity()`, not in the
    /// tool provider.
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
