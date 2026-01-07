//
//  AgentConfiguration.swift
//  SwiftAgent
//
//  Created by SwiftAgent on 2025/01/15.
//

import Foundation

#if USE_OTHER_MODELS

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
    /// Defaults to `ToolPipeline.default` which includes `PermissionMiddleware`
    /// and `SandboxMiddleware` with permissive configurations. This enables
    /// `.guardrail { }` to work automatically without explicit `withSecurity()`.
    ///
    /// ## Example
    ///
    /// ```swift
    /// // Default pipeline enables guardrails automatically
    /// MyStep()
    ///     .guardrail { Deny(.bash("rm:*")) }
    ///     .run(input)  // Permission check enforced
    ///
    /// // Custom pipeline
    /// let pipeline = ToolPipeline()
    ///     .use(LoggingMiddleware())
    ///     .use(PermissionMiddleware(configuration: .standard))
    ///     .use(TimeoutMiddleware(duration: .seconds(30)))
    ///
    /// let config = AgentConfiguration(...)
    ///     .withPipeline(pipeline)
    ///
    /// // Disable all middleware
    /// let config = AgentConfiguration(...)
    ///     .withPipeline(.empty)
    /// ```
    public var toolPipeline: ToolPipeline

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
    ///   - toolPipeline: Tool execution middleware pipeline (default: .default).
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
        toolPipeline: ToolPipeline = .default,
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
    ///   - toolPipeline: Tool execution middleware pipeline (default: .default).
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
        toolPipeline: ToolPipeline = .default,
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
    public func withMiddleware(_ middleware: any ToolMiddleware) -> AgentConfiguration {
        var copy = self
        copy.toolPipeline.use(middleware)
        return copy
    }

    /// Returns a copy with no security middleware.
    ///
    /// Use this to completely disable permission and sandbox checks.
    /// **Warning**: This removes all security protections.
    ///
    /// ## Example
    ///
    /// ```swift
    /// // For testing only
    /// let config = AgentConfiguration(...)
    ///     .withoutSecurity()
    /// ```
    public func withoutSecurity() -> AgentConfiguration {
        var copy = self
        copy.toolPipeline = .empty
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

    // MARK: - Security Configuration

    /// Returns a copy with security configuration applied.
    ///
    /// This configures both permission checking and sandboxing for tool execution.
    /// Both are implemented as middleware in the tool pipeline, achieving clean
    /// layer separation:
    ///
    /// - **PermissionMiddleware**: Checks allow/deny rules before execution
    /// - **SandboxMiddleware**: Intercepts Bash commands and runs them in sandbox
    ///
    /// **Note**: This replaces the default pipeline with custom security settings.
    /// If you want to add middleware to the existing pipeline, use `withMiddleware()`.
    ///
    /// ## Example
    ///
    /// ```swift
    /// // Standard security with CLI prompts
    /// let config = AgentConfiguration(...)
    ///     .withSecurity(.standard.withHandler(CLIPermissionHandler()))
    ///
    /// // Development mode (permissive)
    /// let config = AgentConfiguration(...)
    ///     .withSecurity(.development)
    ///
    /// // Custom security rules
    /// let security = SecurityConfiguration(
    ///     permissions: PermissionConfiguration(
    ///         allow: [.tool("Read"), .bash("git:*")],
    ///         deny: [.bash("rm:*")],
    ///         defaultAction: .ask,
    ///         handler: CLIPermissionHandler()
    ///     ),
    ///     sandbox: .standard
    /// )
    /// let config = AgentConfiguration(...)
    ///     .withSecurity(security)
    /// ```
    ///
    /// ## Execution Flow
    ///
    /// ```
    /// Tool Request
    ///     │
    ///     ▼
    /// PermissionMiddleware (allow/deny/ask)
    ///     │
    ///     ▼
    /// SandboxMiddleware (intercept Bash, run in sandbox)
    ///     │
    ///     ▼
    /// Tool Execution
    /// ```
    ///
    /// - Parameter security: The security configuration to apply.
    /// - Returns: A new configuration with security enabled.
    public func withSecurity(_ security: SecurityConfiguration) -> AgentConfiguration {
        var copy = self

        // Replace the pipeline with security-configured one
        let pipeline = ToolPipeline()
            .use(PermissionMiddleware(configuration: security.permissions))

        // Add sandbox middleware if configured (runs after permission check)
        // SandboxMiddleware injects config via withContext(SandboxContext.self),
        // ExecuteCommandTool reads it via @Context(SandboxContext.self)
        if let sandboxConfig = security.sandbox {
            pipeline.use(SandboxMiddleware(configuration: sandboxConfig))
        }

        copy.toolPipeline = pipeline
        return copy
    }

    /// Returns a copy with read-only security (no write/execute).
    ///
    /// Convenience method for quick read-only mode setup.
    public func withReadOnlySecurity() -> AgentConfiguration {
        withSecurity(.readOnly)
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
    /// Uses standard security with permission checking and sandboxing.
    /// Prompts for confirmation on dangerous operations.
    ///
    /// - Parameters:
    ///   - modelProvider: Model provider for the agent.
    ///   - workingDirectory: Working directory for file operations.
    ///   - permissionHandler: Handler for permission prompts (default: CLIPermissionHandler).
    ///   - toolPipeline: Additional tool middleware pipeline (default: nil).
    public static func codeAssistant(
        modelProvider: any ModelProvider,
        workingDirectory: String = FileManager.default.currentDirectoryPath,
        permissionHandler: (any PermissionHandler)? = nil,
        toolPipeline: ToolPipeline? = nil
    ) -> AgentConfiguration {
        // Base security configuration
        let security = SecurityConfiguration.standard
            .withHandler(permissionHandler ?? CLIPermissionHandler())

        // Default pipeline with logging and timeout
        let pipeline = toolPipeline ?? ToolPipeline()
        pipeline.use(LoggingMiddleware())
        pipeline.use(TimeoutMiddleware(duration: .seconds(60)))

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
        ).withSecurity(security)
    }

    /// Creates a configuration for code review.
    ///
    /// Uses read-only security (no write or execute operations).
    public static func codeReviewer(
        modelProvider: any ModelProvider,
        workingDirectory: String = FileManager.default.currentDirectoryPath,
        toolPipeline: ToolPipeline? = nil
    ) -> AgentConfiguration {
        // Default read-only pipeline for code reviewer
        let pipeline = toolPipeline ?? ToolPipeline()
        pipeline.use(LoggingMiddleware())

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
        ).withSecurity(.readOnly)
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

#endif
