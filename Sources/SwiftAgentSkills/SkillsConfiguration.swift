//
//  SkillsConfiguration.swift
//  SwiftAgent
//
//  Created by SwiftAgent on 2025/01/15.
//

import Foundation

/// Configuration for agent skills.
///
/// Use this to configure how skills are discovered and managed by an agent.
///
/// ## Usage
///
/// ```swift
/// // Enable auto-discovery from standard paths
/// let config = AgentConfiguration(
///     instructions: Instructions("..."),
///     modelProvider: myProvider,
///     skills: .autoDiscover()
/// )
///
/// // Use a custom registry
/// let registry = SkillRegistry()
/// await registry.register(mySkills)
/// let config = AgentConfiguration(
///     instructions: Instructions("..."),
///     modelProvider: myProvider,
///     skills: .custom(registry: registry)
/// )
/// ```
public struct SkillsConfiguration: Sendable {

    /// The skill registry.
    ///
    /// If nil and `autoDiscover` is true, a registry will be created automatically.
    public var registry: SkillRegistry?

    /// Whether to automatically discover skills from standard paths.
    ///
    /// Standard paths include:
    /// - `~/.agent/skills/` (user-level)
    /// - `./.agent/skills/` (project-level)
    /// - `$AGENT_SKILLS_PATH` (environment variable)
    public var autoDiscover: Bool

    /// Additional paths to search for skills.
    public var searchPaths: [String]

    // MARK: - Initialization

    /// Creates a skills configuration.
    ///
    /// - Parameters:
    ///   - registry: Existing skill registry (optional).
    ///   - autoDiscover: Whether to auto-discover skills.
    ///   - searchPaths: Additional search paths.
    public init(
        registry: SkillRegistry? = nil,
        autoDiscover: Bool = true,
        searchPaths: [String] = []
    ) {
        self.registry = registry
        self.autoDiscover = autoDiscover
        self.searchPaths = searchPaths
    }

    // MARK: - Factory Methods

    /// Creates a configuration with auto-discovery enabled.
    ///
    /// - Parameter additionalPaths: Additional paths to search.
    /// - Returns: Configuration with auto-discovery.
    public static func autoDiscover(
        additionalPaths: [String] = []
    ) -> SkillsConfiguration {
        SkillsConfiguration(
            autoDiscover: true,
            searchPaths: additionalPaths
        )
    }

    /// Creates a configuration with a custom registry.
    ///
    /// - Parameters:
    ///   - registry: The skill registry to use.
    ///   - autoDiscover: Whether to also auto-discover skills.
    /// - Returns: Configuration with custom registry.
    public static func custom(
        registry: SkillRegistry,
        autoDiscover: Bool = false
    ) -> SkillsConfiguration {
        SkillsConfiguration(
            registry: registry,
            autoDiscover: autoDiscover
        )
    }

    /// Disabled skills configuration.
    public static let disabled = SkillsConfiguration(
        registry: nil,
        autoDiscover: false,
        searchPaths: []
    )
}
