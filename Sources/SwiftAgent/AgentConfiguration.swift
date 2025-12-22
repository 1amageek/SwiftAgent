//
//  AgentConfiguration.swift
//  SwiftAgent
//
//  Created by SwiftAgent on 2025/01/15.
//

import Foundation

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

    /// Whether to automatically save sessions.
    public var autoSave: Bool

    /// Session store for persistence.
    public var sessionStore: (any SessionStore)?

    // MARK: - Pipeline Configuration

    /// Advanced tool execution options.
    ///
    /// Configure hooks, permissions, timeout, and retry behavior for tool execution.
    public var pipelineConfiguration: ToolPipelineConfiguration

    // MARK: - Skills Configuration

    /// Skills configuration for this agent.
    ///
    /// Set to `nil` to disable skills, or use `.autoDiscover()` to enable
    /// automatic skill discovery from standard paths.
    public var skills: SkillsConfiguration?

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
    ///   - autoSave: Whether to auto-save sessions (default: false).
    ///   - sessionStore: Session store for persistence (default: nil).
    ///   - pipelineConfiguration: Pipeline configuration for tool execution (default: .default).
    ///   - skills: Skills configuration (default: nil, skills disabled).
    public init(
        instructions: Instructions,
        tools: ToolConfiguration = .preset(.default),
        subagents: [SubagentDefinition] = [],
        modelProvider: any ModelProvider,
        modelConfiguration: ModelConfiguration = .default,
        workingDirectory: String = FileManager.default.currentDirectoryPath,
        autoSave: Bool = false,
        sessionStore: (any SessionStore)? = nil,
        pipelineConfiguration: ToolPipelineConfiguration = .default,
        skills: SkillsConfiguration? = nil
    ) {
        self.instructions = instructions
        self.tools = tools
        self.subagents = subagents
        self.modelProvider = modelProvider
        self.modelConfiguration = modelConfiguration
        self.workingDirectory = workingDirectory
        self.autoSave = autoSave
        self.sessionStore = sessionStore
        self.pipelineConfiguration = pipelineConfiguration
        self.skills = skills
    }

    /// Creates an agent configuration with an instructions builder.
    ///
    /// - Parameters:
    ///   - tools: Tool configuration.
    ///   - subagents: Subagent definitions.
    ///   - modelProvider: Model provider for the agent.
    ///   - modelConfiguration: Model configuration options.
    ///   - workingDirectory: Working directory for file operations.
    ///   - autoSave: Whether to auto-save sessions.
    ///   - sessionStore: Session store for persistence.
    ///   - pipelineConfiguration: Pipeline configuration for tool execution.
    ///   - skills: Skills configuration (default: nil, skills disabled).
    ///   - instructions: Instructions builder.
    public init(
        tools: ToolConfiguration = .preset(.default),
        subagents: [SubagentDefinition] = [],
        modelProvider: any ModelProvider,
        modelConfiguration: ModelConfiguration = .default,
        workingDirectory: String = FileManager.default.currentDirectoryPath,
        autoSave: Bool = false,
        sessionStore: (any SessionStore)? = nil,
        pipelineConfiguration: ToolPipelineConfiguration = .default,
        skills: SkillsConfiguration? = nil,
        @InstructionsBuilder instructions: () throws -> Instructions
    ) rethrows {
        self.instructions = try instructions()
        self.tools = tools
        self.subagents = subagents
        self.modelProvider = modelProvider
        self.modelConfiguration = modelConfiguration
        self.workingDirectory = workingDirectory
        self.autoSave = autoSave
        self.sessionStore = sessionStore
        self.pipelineConfiguration = pipelineConfiguration
        self.skills = skills
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

    /// Returns a copy with skills enabled.
    ///
    /// - Parameter configuration: Skills configuration.
    /// - Returns: A copy with skills configured.
    public func withSkills(_ configuration: SkillsConfiguration = .autoDiscover()) -> AgentConfiguration {
        var copy = self
        copy.skills = configuration
        return copy
    }

    /// Returns a copy with skills disabled.
    public func withoutSkills() -> AgentConfiguration {
        var copy = self
        copy.skills = nil
        return copy
    }
}

// MARK: - Validation

extension AgentConfiguration {

    /// Validates the configuration.
    ///
    /// - Throws: `AgentError.invalidConfiguration` if validation fails.
    public func validate() throws {
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
