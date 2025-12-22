//
//  ToolConfiguration.swift
//  SwiftAgent
//
//  Created by SwiftAgent on 2025/01/15.
//

import Foundation
import OpenFoundationModels

/// Configuration for tools available to an agent.
///
/// `ToolConfiguration` provides flexible control over which tools are available
/// during agent execution, similar to Claude Agent SDK's `tools` option.
///
/// ## Usage
///
/// ```swift
/// // Use default preset (all built-in tools)
/// let config = ToolConfiguration.preset(.default)
///
/// // Use specific tools only
/// let config = ToolConfiguration.allowlist([ReadTool(), WriteTool()])
///
/// // Disable all tools
/// let config = ToolConfiguration.disabled
/// ```
public enum ToolConfiguration: Sendable {

    /// Use a predefined set of tools.
    case preset(ToolPreset)

    /// Use only the specified tools (allowlist).
    case allowlist([any Tool])

    /// Use custom tools directly.
    case custom([any Tool])

    /// Disable all built-in tools.
    case disabled

    // MARK: - Convenience Initializers

    /// Creates a configuration with the default tool preset.
    public static var `default`: ToolConfiguration {
        .preset(.default)
    }

    /// Creates a configuration with read-only tools.
    public static var readOnly: ToolConfiguration {
        .preset(.readOnly)
    }

    /// Creates a configuration with file-only tools.
    public static var fileOnly: ToolConfiguration {
        .preset(.fileOnly)
    }
}

// MARK: - Tool Presets

extension ToolConfiguration {

    /// Predefined tool presets for common use cases.
    public enum ToolPreset: String, Sendable, CaseIterable {

        /// All default tools: Read, Write, Edit, MultiEdit, Grep, Glob, ExecuteCommand, Git, URLFetch
        case `default`

        /// File operations only: Read, Write, Edit, MultiEdit
        case fileOnly

        /// Read-only operations: Read, Grep, Glob
        case readOnly

        /// Development tools: Read, Write, Edit, ExecuteCommand, Git
        case development

        /// Minimal tools: Read only
        case minimal

        /// Tool names included in this preset.
        ///
        /// These names correspond to the actual tool names defined in AgentTools module:
        /// - `file_read`: ReadTool
        /// - `file_write`: WriteTool
        /// - `file_edit`: EditTool
        /// - `file_multi_edit`: MultiEditTool
        /// - `text_search`: GrepTool
        /// - `file_pattern`: GlobTool
        /// - `command_execute`: ExecuteCommandTool
        /// - `git_command`: GitTool
        /// - `web_fetch`: URLFetchTool
        public var toolNames: [String] {
            switch self {
            case .default:
                return [
                    "file_read",
                    "file_write",
                    "file_edit",
                    "file_multi_edit",
                    "text_search",
                    "file_pattern",
                    "command_execute",
                    "git_command",
                    "web_fetch"
                ]
            case .fileOnly:
                return [
                    "file_read",
                    "file_write",
                    "file_edit",
                    "file_multi_edit"
                ]
            case .readOnly:
                return [
                    "file_read",
                    "text_search",
                    "file_pattern"
                ]
            case .development:
                return [
                    "file_read",
                    "file_write",
                    "file_edit",
                    "command_execute",
                    "git_command"
                ]
            case .minimal:
                return ["file_read"]
            }
        }
    }
}

// MARK: - Tool Resolution

extension ToolConfiguration {

    /// Resolves the configuration to an array of tools.
    ///
    /// - Parameter toolProvider: A provider that can create tools by name.
    /// - Returns: Array of resolved tools.
    public func resolve(using toolProvider: ToolProvider) -> [any Tool] {
        switch self {
        case .preset(let preset):
            return toolProvider.tools(for: preset.toolNames)
        case .allowlist(let tools):
            return tools
        case .custom(let tools):
            return tools
        case .disabled:
            return []
        }
    }

    /// Checks if a specific tool is allowed by this configuration.
    ///
    /// - Parameter toolName: The name of the tool to check.
    /// - Returns: `true` if the tool is allowed.
    public func allows(toolName: String) -> Bool {
        switch self {
        case .preset(let preset):
            return preset.toolNames.contains(toolName)
        case .allowlist(let tools):
            return tools.contains { $0.name == toolName }
        case .custom(let tools):
            return tools.contains { $0.name == toolName }
        case .disabled:
            return false
        }
    }

    /// Returns the names of all allowed tools.
    public var allowedToolNames: [String] {
        switch self {
        case .preset(let preset):
            return preset.toolNames
        case .allowlist(let tools):
            return tools.map { $0.name }
        case .custom(let tools):
            return tools.map { $0.name }
        case .disabled:
            return []
        }
    }
}

// MARK: - Tool Provider Protocol

/// A protocol for providing tools by name.
///
/// Implement this protocol to customize how tools are created and configured.
public protocol ToolProvider: Sendable {

    /// Returns tools matching the specified names.
    ///
    /// - Parameter names: The names of tools to retrieve.
    /// - Returns: Array of tools matching the names.
    func tools(for names: [String]) -> [any Tool]

    /// Returns a single tool by name.
    ///
    /// - Parameter name: The name of the tool.
    /// - Returns: The tool if found, `nil` otherwise.
    func tool(named name: String) -> (any Tool)?
}

// MARK: - Default Tool Provider

/// A base tool provider that serves as an extension point.
///
/// `DefaultToolProvider` provides the basic structure for tool provisioning.
/// To use with actual tools, use `AgentToolsProvider` from the `AgentTools` module,
/// or create a custom implementation that returns your tools.
///
/// ## Usage with AgentTools
///
/// ```swift
/// import AgentTools
///
/// let provider = AgentToolsProvider(workingDirectory: "/path/to/work")
/// let tools = provider.tools(for: ToolPreset.default.toolNames)
/// ```
///
/// ## Custom Implementation
///
/// ```swift
/// struct MyToolProvider: ToolProvider {
///     func tool(named name: String) -> (any Tool)? {
///         switch name {
///         case "my_tool": return MyTool()
///         default: return nil
///         }
///     }
/// }
/// ```
public struct DefaultToolProvider: ToolProvider {

    /// The working directory for file operations.
    public let workingDirectory: String

    /// Factory function for creating tools by name.
    private let toolFactory: @Sendable (String, String) -> (any Tool)?

    /// Creates a new default tool provider.
    ///
    /// - Parameters:
    ///   - workingDirectory: The working directory for file operations.
    ///   - toolFactory: Optional factory function to create tools. The factory receives
    ///     the tool name and working directory, and should return the tool instance.
    public init(
        workingDirectory: String = FileManager.default.currentDirectoryPath,
        toolFactory: @escaping @Sendable (String, String) -> (any Tool)? = { _, _ in nil }
    ) {
        self.workingDirectory = workingDirectory
        self.toolFactory = toolFactory
    }

    public func tools(for names: [String]) -> [any Tool] {
        return names.compactMap { tool(named: $0) }
    }

    public func tool(named name: String) -> (any Tool)? {
        return toolFactory(name, workingDirectory)
    }
}

// MARK: - Tool Configuration Builder

/// A result builder for creating tool configurations.
@resultBuilder
public struct ToolConfigurationBuilder {

    public static func buildBlock(_ tools: any Tool...) -> [any Tool] {
        tools
    }

    public static func buildOptional(_ tools: [any Tool]?) -> [any Tool] {
        tools ?? []
    }

    public static func buildEither(first tools: [any Tool]) -> [any Tool] {
        tools
    }

    public static func buildEither(second tools: [any Tool]) -> [any Tool] {
        tools
    }

    public static func buildArray(_ components: [[any Tool]]) -> [any Tool] {
        components.flatMap { $0 }
    }
}

extension ToolConfiguration {

    /// Creates a custom tool configuration using a builder.
    ///
    /// ```swift
    /// let config = ToolConfiguration.build {
    ///     ReadTool()
    ///     WriteTool()
    ///     if includeGit {
    ///         GitTool()
    ///     }
    /// }
    /// ```
    public static func build(
        @ToolConfigurationBuilder _ builder: () -> [any Tool]
    ) -> ToolConfiguration {
        .custom(builder())
    }
}

// MARK: - Equatable Support

extension ToolConfiguration {

    /// Compares two configurations by their allowed tool names.
    public func isEquivalent(to other: ToolConfiguration) -> Bool {
        Set(self.allowedToolNames) == Set(other.allowedToolNames)
    }
}

// MARK: - CustomStringConvertible

extension ToolConfiguration: CustomStringConvertible {

    public var description: String {
        switch self {
        case .preset(let preset):
            return "preset(\(preset.rawValue))"
        case .allowlist(let tools):
            return "allowlist([\(tools.map { $0.name }.joined(separator: ", "))])"
        case .custom(let tools):
            return "custom([\(tools.map { $0.name }.joined(separator: ", "))])"
        case .disabled:
            return "disabled"
        }
    }
}
