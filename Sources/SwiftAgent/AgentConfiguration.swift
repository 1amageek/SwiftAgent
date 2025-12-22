//
//  AgentConfiguration.swift
//  SwiftAgent
//
//  Created by SwiftAgent on 2025/01/15.
//

import Foundation
import OpenFoundationModels

/// Configuration for an agent session.
///
/// `AgentConfiguration` defines all the settings for an agent, including
/// instructions, tools, subagents, and model configuration. This is similar
/// to the options object in Claude Agent SDK.
///
/// ## Usage
///
/// ```swift
/// let configuration = AgentConfiguration(
///     instructions: Instructions {
///         "You are a helpful coding assistant."
///         "You can read, write, and edit files."
///     },
///     tools: .preset(.default),
///     modelProvider: myModelProvider
/// )
/// ```
public struct AgentConfiguration: Sendable {

    // MARK: - Core Properties

    /// Instructions that define the agent's behavior.
    ///
    /// This is equivalent to Claude Agent SDK's `systemPrompt`.
    public var instructions: Instructions

    /// Tool configuration for the agent.
    public var tools: ToolConfiguration

    /// Subagent definitions available to this agent.
    public var subagents: [SubagentDefinition]

    /// Model provider for the agent.
    public var modelProvider: any ModelProvider

    /// Model configuration options.
    public var modelConfiguration: ModelConfiguration

    // MARK: - Session Options

    /// Working directory for file operations.
    public var workingDirectory: String

    /// Maximum number of tool execution loops per prompt.
    public var maxToolLoops: Int

    /// Timeout for the entire prompt execution.
    public var promptTimeout: Duration?

    /// Timeout for individual tool executions.
    public var toolTimeout: Duration

    // MARK: - Behavior Options

    /// Whether to automatically save sessions.
    public var autoSave: Bool

    /// Session store for persistence.
    public var sessionStore: (any SessionStore)?

    /// Whether to include tool results in the response.
    public var includeToolResults: Bool

    /// Whether to stream responses by default.
    public var streamByDefault: Bool

    // MARK: - Advanced Tool Options

    /// Advanced tool execution options.
    ///
    /// Configure hooks, permissions, timeout, and retry behavior for tool execution.
    public var pipelineConfiguration: ToolPipelineConfiguration

    // MARK: - Initialization

    /// Creates an agent configuration.
    ///
    /// - Parameters:
    ///   - instructions: Instructions defining agent behavior.
    ///   - tools: Tool configuration (default: preset(.default)).
    ///   - subagents: Subagent definitions (default: empty).
    ///   - modelProvider: Model provider for the agent.
    ///   - modelConfiguration: Model configuration options.
    ///   - workingDirectory: Working directory for file operations.
    ///   - maxToolLoops: Maximum tool execution loops (default: 20).
    ///   - promptTimeout: Timeout for prompt execution (default: nil).
    ///   - toolTimeout: Timeout for tool execution (default: 60 seconds).
    ///   - autoSave: Whether to auto-save sessions (default: false).
    ///   - sessionStore: Session store for persistence (default: nil).
    ///   - includeToolResults: Include tool results in response (default: true).
    ///   - streamByDefault: Stream responses by default (default: false).
    ///   - pipelineConfiguration: Advanced tool execution options (default: .default).
    public init(
        instructions: Instructions,
        tools: ToolConfiguration = .preset(.default),
        subagents: [SubagentDefinition] = [],
        modelProvider: any ModelProvider,
        modelConfiguration: ModelConfiguration = .default,
        workingDirectory: String = FileManager.default.currentDirectoryPath,
        maxToolLoops: Int = 20,
        promptTimeout: Duration? = nil,
        toolTimeout: Duration = .seconds(60),
        autoSave: Bool = false,
        sessionStore: (any SessionStore)? = nil,
        includeToolResults: Bool = true,
        streamByDefault: Bool = false,
        pipelineConfiguration: ToolPipelineConfiguration = .default
    ) {
        self.instructions = instructions
        self.tools = tools
        self.subagents = subagents
        self.modelProvider = modelProvider
        self.modelConfiguration = modelConfiguration
        self.workingDirectory = workingDirectory
        self.maxToolLoops = maxToolLoops
        self.promptTimeout = promptTimeout
        self.toolTimeout = toolTimeout
        self.autoSave = autoSave
        self.sessionStore = sessionStore
        self.includeToolResults = includeToolResults
        self.streamByDefault = streamByDefault
        self.pipelineConfiguration = pipelineConfiguration
    }

    /// Creates an agent configuration with an instructions builder.
    ///
    /// - Parameters:
    ///   - tools: Tool configuration.
    ///   - subagents: Subagent definitions.
    ///   - modelProvider: Model provider for the agent.
    ///   - modelConfiguration: Model configuration options.
    ///   - workingDirectory: Working directory for file operations.
    ///   - maxToolLoops: Maximum tool execution loops.
    ///   - promptTimeout: Timeout for prompt execution.
    ///   - toolTimeout: Timeout for tool execution.
    ///   - autoSave: Whether to auto-save sessions.
    ///   - sessionStore: Session store for persistence.
    ///   - includeToolResults: Include tool results in response.
    ///   - streamByDefault: Stream responses by default.
    ///   - pipelineConfiguration: Advanced tool execution options.
    ///   - instructions: Instructions builder.
    public init(
        tools: ToolConfiguration = .preset(.default),
        subagents: [SubagentDefinition] = [],
        modelProvider: any ModelProvider,
        modelConfiguration: ModelConfiguration = .default,
        workingDirectory: String = FileManager.default.currentDirectoryPath,
        maxToolLoops: Int = 20,
        promptTimeout: Duration? = nil,
        toolTimeout: Duration = .seconds(60),
        autoSave: Bool = false,
        sessionStore: (any SessionStore)? = nil,
        includeToolResults: Bool = true,
        streamByDefault: Bool = false,
        pipelineConfiguration: ToolPipelineConfiguration = .default,
        @InstructionsBuilder instructions: () throws -> Instructions
    ) rethrows {
        self.instructions = try instructions()
        self.tools = tools
        self.subagents = subagents
        self.modelProvider = modelProvider
        self.modelConfiguration = modelConfiguration
        self.workingDirectory = workingDirectory
        self.maxToolLoops = maxToolLoops
        self.promptTimeout = promptTimeout
        self.toolTimeout = toolTimeout
        self.autoSave = autoSave
        self.sessionStore = sessionStore
        self.includeToolResults = includeToolResults
        self.streamByDefault = streamByDefault
        self.pipelineConfiguration = pipelineConfiguration
    }
}

// MARK: - Builder Pattern

extension AgentConfiguration {

    /// Returns a copy with modified instructions.
    public func with(instructions: Instructions) -> AgentConfiguration {
        var copy = self
        copy.instructions = instructions
        return copy
    }

    /// Returns a copy with modified tools.
    public func with(tools: ToolConfiguration) -> AgentConfiguration {
        var copy = self
        copy.tools = tools
        return copy
    }

    /// Returns a copy with additional subagents.
    public func with(subagents: [SubagentDefinition]) -> AgentConfiguration {
        var copy = self
        copy.subagents = subagents
        return copy
    }

    /// Returns a copy with an added subagent.
    public func adding(subagent: SubagentDefinition) -> AgentConfiguration {
        var copy = self
        copy.subagents.append(subagent)
        return copy
    }

    /// Returns a copy with modified model configuration.
    public func with(modelConfiguration: ModelConfiguration) -> AgentConfiguration {
        var copy = self
        copy.modelConfiguration = modelConfiguration
        return copy
    }

    /// Returns a copy with modified working directory.
    public func with(workingDirectory: String) -> AgentConfiguration {
        var copy = self
        copy.workingDirectory = workingDirectory
        return copy
    }

    /// Returns a copy with modified timeouts.
    public func with(
        promptTimeout: Duration? = nil,
        toolTimeout: Duration? = nil
    ) -> AgentConfiguration {
        var copy = self
        if let pt = promptTimeout {
            copy.promptTimeout = pt
        }
        if let tt = toolTimeout {
            copy.toolTimeout = tt
        }
        return copy
    }

    /// Returns a copy with auto-save enabled.
    public func withAutoSave(_ store: any SessionStore) -> AgentConfiguration {
        var copy = self
        copy.autoSave = true
        copy.sessionStore = store
        return copy
    }

    /// Returns a copy with modified advanced tool options.
    public func with(pipelineConfiguration: ToolPipelineConfiguration) -> AgentConfiguration {
        var copy = self
        copy.pipelineConfiguration = pipelineConfiguration
        return copy
    }

    /// Returns a copy with an additional global tool hook.
    public func withToolHook(_ hook: any ToolExecutionHook) -> AgentConfiguration {
        var copy = self
        copy.pipelineConfiguration = copy.pipelineConfiguration.withHook(hook)
        return copy
    }

    /// Returns a copy with a tool permission delegate.
    public func withPermissionDelegate(_ delegate: any ToolPermissionDelegate) -> AgentConfiguration {
        var copy = self
        copy.pipelineConfiguration = copy.pipelineConfiguration.withPermissionDelegate(delegate)
        return copy
    }
}

// MARK: - Validation

extension AgentConfiguration {

    /// Validates the configuration.
    ///
    /// - Throws: `AgentError.invalidConfiguration` if validation fails.
    public func validate() throws {
        // Validate max tool loops
        if maxToolLoops < 1 {
            throw AgentError.invalidConfiguration(
                reason: "maxToolLoops must be at least 1"
            )
        }

        // Validate tool timeout
        if toolTimeout <= .zero {
            throw AgentError.invalidConfiguration(
                reason: "toolTimeout must be positive"
            )
        }

        // Validate subagent names are unique
        let names = subagents.map { $0.name }
        let uniqueNames = Set(names)
        if names.count != uniqueNames.count {
            throw AgentError.invalidConfiguration(
                reason: "Subagent names must be unique"
            )
        }

        // Validate model configuration
        if let temp = modelConfiguration.temperature {
            if temp < 0 || temp > 2 {
                throw AgentError.invalidConfiguration(
                    reason: "temperature must be between 0 and 2"
                )
            }
        }

        if let topP = modelConfiguration.topP {
            if topP < 0 || topP > 1 {
                throw AgentError.invalidConfiguration(
                    reason: "topP must be between 0 and 1"
                )
            }
        }
    }
}

// MARK: - Convenience Factories

extension AgentConfiguration {

    /// Creates a minimal configuration with just instructions and a model.
    public static func minimal(
        instructions: String,
        modelProvider: any ModelProvider
    ) -> AgentConfiguration {
        AgentConfiguration(
            instructions: Instructions(instructions),
            tools: .disabled,
            modelProvider: modelProvider
        )
    }

    /// Creates a configuration for code assistance.
    public static func codeAssistant(
        modelProvider: any ModelProvider,
        workingDirectory: String = FileManager.default.currentDirectoryPath,
        pipelineConfiguration: ToolPipelineConfiguration = .secure
    ) -> AgentConfiguration {
        AgentConfiguration(
            instructions: Instructions("""
                You are a helpful coding assistant. You can:
                - Read, write, and edit code files
                - Search for patterns in code
                - Execute commands to build and test code
                - Use Git for version control

                Always explain what you're doing and ask for confirmation before making changes.
                """),
            tools: .preset(.development),
            modelProvider: modelProvider,
            modelConfiguration: .code,
            workingDirectory: workingDirectory,
            pipelineConfiguration: pipelineConfiguration
        )
    }

    /// Creates a configuration for code review.
    public static func codeReviewer(
        modelProvider: any ModelProvider,
        workingDirectory: String = FileManager.default.currentDirectoryPath
    ) -> AgentConfiguration {
        AgentConfiguration(
            instructions: Instructions("""
                You are an expert code reviewer. Analyze code for:
                - Bugs and potential issues
                - Performance problems
                - Security vulnerabilities
                - Code style and best practices

                Provide specific, actionable feedback with references to line numbers.
                """),
            tools: .preset(.readOnly),
            modelProvider: modelProvider,
            workingDirectory: workingDirectory
        )
    }
}

// MARK: - CustomStringConvertible

extension AgentConfiguration: CustomStringConvertible {

    public var description: String {
        """
        AgentConfiguration(
            tools: \(tools),
            subagents: \(subagents.count),
            model: \(modelProvider.modelID),
            workingDirectory: \(workingDirectory)
        )
        """
    }
}
