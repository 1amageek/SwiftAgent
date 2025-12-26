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
/// instructions, tools, and model configuration. This is similar
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

    /// Tool execution middleware pipeline.
    ///
    /// The new middleware-based pipeline for tool execution. When set, this takes
    /// precedence over the legacy `pipelineConfiguration`.
    ///
    /// ## Example
    ///
    /// ```swift
    /// let pipeline = ToolPipeline()
    ///     .use(LoggingMiddleware())
    ///     .use(PermissionMiddleware { context in
    ///         context.toolName != "dangerous_tool"
    ///     })
    ///     .use(RetryMiddleware(maxAttempts: 3))
    ///     .use(TimeoutMiddleware(duration: .seconds(30)))
    ///
    /// let config = AgentConfiguration(...)
    ///     .withPipeline(pipeline)
    /// ```
    public var toolPipeline: ToolPipeline?

    // MARK: - Skills Configuration

    /// Skills configuration for this agent.
    ///
    /// Set to `nil` to disable skills, or use `.autoDiscover()` to enable
    /// automatic skill discovery from standard paths.
    public var skills: SkillsConfiguration?

    // MARK: - Context Configuration

    /// Context management configuration for this agent.
    ///
    /// Set to `nil` to disable context management, or use `.default` for
    /// automatic context compaction at 80% threshold.
    ///
    /// ## Example
    ///
    /// ```swift
    /// let config = AgentConfiguration(...)
    ///     .withContext(.default)
    ///
    /// // Or with custom settings
    /// let config = AgentConfiguration(...)
    ///     .withContext(ContextConfiguration(
    ///         compactionThreshold: 0.85,
    ///         strategy: PriorityCompactionStrategy()
    ///     ))
    /// ```
    public var context: ContextConfiguration?

    // MARK: - Initialization

    /// Creates an agent configuration.
    ///
    /// - Parameters:
    ///   - instructions: Instructions defining agent behavior.
    ///   - tools: Tool configuration (default: preset(.default)).
    ///   - modelProvider: Model provider for the agent.
    ///   - modelConfiguration: Model configuration options.
    ///   - workingDirectory: Working directory for file operations.
    ///   - autoSave: Whether to auto-save sessions (default: false).
    ///   - sessionStore: Session store for persistence (default: nil).
    ///   - toolPipeline: Tool execution middleware pipeline (default: nil).
    ///   - skills: Skills configuration (default: nil, skills disabled).
    ///   - context: Context management configuration (default: nil, context management disabled).
    public init(
        instructions: Instructions,
        tools: ToolConfiguration = .preset(.default),
        modelProvider: any ModelProvider,
        modelConfiguration: ModelConfiguration = .default,
        workingDirectory: String = FileManager.default.currentDirectoryPath,
        autoSave: Bool = false,
        sessionStore: (any SessionStore)? = nil,
        toolPipeline: ToolPipeline? = nil,
        skills: SkillsConfiguration? = nil,
        context: ContextConfiguration? = nil
    ) {
        self.instructions = instructions
        self.tools = tools
        self.modelProvider = modelProvider
        self.modelConfiguration = modelConfiguration
        self.workingDirectory = workingDirectory
        self.autoSave = autoSave
        self.sessionStore = sessionStore
        self.toolPipeline = toolPipeline
        self.skills = skills
        self.context = context
    }

    /// Creates an agent configuration with an instructions builder.
    ///
    /// - Parameters:
    ///   - tools: Tool configuration.
    ///   - modelProvider: Model provider for the agent.
    ///   - modelConfiguration: Model configuration options.
    ///   - workingDirectory: Working directory for file operations.
    ///   - autoSave: Whether to auto-save sessions.
    ///   - sessionStore: Session store for persistence.
    ///   - toolPipeline: Tool execution middleware pipeline (default: nil).
    ///   - skills: Skills configuration (default: nil, skills disabled).
    ///   - context: Context management configuration (default: nil, context management disabled).
    ///   - instructions: Instructions builder.
    public init(
        tools: ToolConfiguration = .preset(.default),
        modelProvider: any ModelProvider,
        modelConfiguration: ModelConfiguration = .default,
        workingDirectory: String = FileManager.default.currentDirectoryPath,
        autoSave: Bool = false,
        sessionStore: (any SessionStore)? = nil,
        toolPipeline: ToolPipeline? = nil,
        skills: SkillsConfiguration? = nil,
        context: ContextConfiguration? = nil,
        @InstructionsBuilder instructions: () throws -> Instructions
    ) rethrows {
        self.instructions = try instructions()
        self.tools = tools
        self.modelProvider = modelProvider
        self.modelConfiguration = modelConfiguration
        self.workingDirectory = workingDirectory
        self.autoSave = autoSave
        self.sessionStore = sessionStore
        self.toolPipeline = toolPipeline
        self.skills = skills
        self.context = context
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

    /// Returns a copy with the specified tool middleware pipeline.
    ///
    /// ## Example
    ///
    /// ```swift
    /// let pipeline = ToolPipeline()
    ///     .use(LoggingMiddleware())
    ///     .use(RetryMiddleware(maxAttempts: 3))
    ///
    /// let config = AgentConfiguration(...)
    ///     .withPipeline(pipeline)
    /// ```
    public func withPipeline(_ pipeline: ToolPipeline) -> AgentConfiguration {
        var copy = self
        copy.toolPipeline = pipeline
        return copy
    }

    /// Returns a copy with additional middleware added to the pipeline.
    ///
    /// If no pipeline exists, creates a new one with the middleware.
    public func withMiddleware(_ middleware: any ToolMiddleware) -> AgentConfiguration {
        var copy = self
        if copy.toolPipeline == nil {
            copy.toolPipeline = ToolPipeline()
        }
        copy.toolPipeline?.use(middleware)
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

    /// Returns a copy with context management enabled.
    ///
    /// - Parameter configuration: Context configuration (default: .default).
    /// - Returns: A copy with context management configured.
    public func withContext(_ configuration: ContextConfiguration = .default) -> AgentConfiguration {
        var copy = self
        copy.context = configuration
        return copy
    }

    /// Returns a copy with context management disabled.
    public func withoutContext() -> AgentConfiguration {
        var copy = self
        copy.context = nil
        return copy
    }
}

// MARK: - Validation

extension AgentConfiguration {

    /// Validates the configuration.
    ///
    /// - Throws: `AgentError.invalidConfiguration` if validation fails.
    public func validate() throws {
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
    ///
    /// Uses a secure middleware pipeline with permission checking for dangerous operations.
    public static func codeAssistant(
        modelProvider: any ModelProvider,
        workingDirectory: String = FileManager.default.currentDirectoryPath,
        toolPipeline: ToolPipeline? = nil
    ) -> AgentConfiguration {
        // Default secure pipeline for code assistant
        let pipeline = toolPipeline ?? ToolPipeline()
            .use(LoggingMiddleware())
            .use(PermissionMiddleware.blockList(["rm", "sudo", "chmod 777"]))
            .use(TimeoutMiddleware(duration: .seconds(60)))

        return AgentConfiguration(
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
            toolPipeline: pipeline
        )
    }

    /// Creates a configuration for code review.
    ///
    /// Uses a read-only tool preset with logging middleware.
    public static func codeReviewer(
        modelProvider: any ModelProvider,
        workingDirectory: String = FileManager.default.currentDirectoryPath,
        toolPipeline: ToolPipeline? = nil
    ) -> AgentConfiguration {
        // Default read-only pipeline for code reviewer
        let pipeline = toolPipeline ?? ToolPipeline()
            .use(LoggingMiddleware())

        return AgentConfiguration(
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
            workingDirectory: workingDirectory,
            toolPipeline: pipeline
        )
    }
}

// MARK: - CustomStringConvertible

extension AgentConfiguration: CustomStringConvertible {

    public var description: String {
        """
        AgentConfiguration(
            tools: \(tools),
            model: \(modelProvider.modelID),
            workingDirectory: \(workingDirectory)
        )
        """
    }
}
