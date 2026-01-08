//
//  SkillRegistry.swift
//  SwiftAgent
//
//  Created by SwiftAgent on 2025/01/15.
//

import Foundation

/// Registry for managing discovered skills.
///
/// `SkillRegistry` provides a central place for registering, retrieving,
/// and activating skills. It follows the progressive disclosure model
/// where skills start with only metadata loaded, and full instructions
/// are loaded on activation.
///
/// ## Usage
///
/// ```swift
/// let registry = SkillRegistry()
///
/// // Register skills (metadata only)
/// let skills = try SkillDiscovery.discoverAll()
/// await registry.register(skills)
///
/// // Generate prompt for available skills
/// let prompt = await registry.generateAvailableSkillsPrompt()
///
/// // Activate a skill when needed
/// let skill = try await registry.activate("pdf-processing")
/// print(skill.instructions)
/// ```
public actor SkillRegistry {

    // MARK: - State

    /// All registered skills (metadata only initially).
    private var skills: [String: Skill] = [:]

    /// Currently activated skills (full instructions loaded).
    private var activeSkills: Set<String> = []

    // MARK: - Initialization

    /// Creates an empty registry.
    public init() {}

    /// Creates a registry with initial skills.
    ///
    /// - Parameter skills: Skills to register.
    public init(skills: [Skill]) {
        for skill in skills {
            self.skills[skill.id] = skill
        }
    }

    // MARK: - Registration

    /// Registers a skill.
    ///
    /// - Parameter skill: The skill to register.
    public func register(_ skill: Skill) {
        skills[skill.id] = skill
    }

    /// Registers multiple skills.
    ///
    /// - Parameter newSkills: The skills to register.
    public func register(_ newSkills: [Skill]) {
        for skill in newSkills {
            skills[skill.id] = skill
        }
    }

    /// Unregisters a skill by name.
    ///
    /// - Parameter name: The name of the skill to unregister.
    /// - Returns: The removed skill, if any.
    @discardableResult
    public func unregister(_ name: String) -> Skill? {
        activeSkills.remove(name)
        return skills.removeValue(forKey: name)
    }

    /// Clears all registered skills.
    public func clear() {
        skills.removeAll()
        activeSkills.removeAll()
    }

    // MARK: - Retrieval

    /// Gets a skill by name.
    ///
    /// - Parameter name: The name of the skill.
    /// - Returns: The skill, or nil if not found.
    public func get(_ name: String) -> Skill? {
        skills[name]
    }

    /// Gets all registered skill names.
    public var registeredNames: [String] {
        Array(skills.keys).sorted()
    }

    /// Gets all registered skills.
    public var allSkills: [Skill] {
        Array(skills.values).sorted { $0.id < $1.id }
    }

    /// Checks if a skill is registered.
    ///
    /// - Parameter name: The name to check.
    /// - Returns: `true` if registered.
    public func contains(_ name: String) -> Bool {
        skills[name] != nil
    }

    /// The number of registered skills.
    public var count: Int {
        skills.count
    }

    // MARK: - Activation

    /// Activates a skill (loads full instructions).
    ///
    /// If the skill is already activated, returns the cached version.
    ///
    /// - Parameter name: The skill name.
    /// - Returns: The activated skill with full instructions.
    /// - Throws: `SkillError.skillNotFound` if skill doesn't exist.
    public func activate(_ name: String) throws -> Skill {
        guard let skill = skills[name] else {
            throw SkillError.skillNotFound(name: name)
        }

        // If already fully loaded, return it
        if skill.isFullyLoaded {
            activeSkills.insert(name)
            return skill
        }

        // Load full skill
        let fullSkill = try SkillLoader.loadFull(from: skill)
        skills[name] = fullSkill
        activeSkills.insert(name)

        return fullSkill
    }

    /// Deactivates a skill (marks as inactive, but keeps in registry).
    ///
    /// Note: This doesn't unload the instructions, just marks the skill
    /// as inactive for prompt generation purposes.
    ///
    /// - Parameter name: The skill name.
    public func deactivate(_ name: String) {
        activeSkills.remove(name)
    }

    /// Deactivates all skills.
    public func deactivateAll() {
        activeSkills.removeAll()
    }

    /// Checks if a skill is active.
    ///
    /// - Parameter name: The skill name.
    /// - Returns: `true` if the skill is active.
    public func isActive(_ name: String) -> Bool {
        activeSkills.contains(name)
    }

    /// Gets all active skill names.
    public var activeSkillNames: [String] {
        Array(activeSkills).sorted()
    }

    /// Gets all active skills.
    public var activeSkillList: [Skill] {
        activeSkillNames.compactMap { skills[$0] }
    }

    // MARK: - Prompt Generation

    /// Generates `<available_skills>` XML for system prompt.
    ///
    /// This includes only name and description for each skill,
    /// following the progressive disclosure model.
    ///
    /// ## Example Output
    ///
    /// ```xml
    /// <available_skills>
    ///   <skill>
    ///     <name>pdf-processing</name>
    ///     <description>Extract text and tables from PDF files.</description>
    ///     <location>/path/to/skills/pdf-processing/SKILL.md</location>
    ///   </skill>
    /// </available_skills>
    /// ```
    ///
    /// - Returns: XML string for injection into system prompt.
    public func generateAvailableSkillsPrompt() -> String {
        guard !skills.isEmpty else {
            return ""
        }

        var lines: [String] = ["<available_skills>"]

        for skill in allSkills {
            lines.append("  <skill>")
            lines.append("    <name>\(escapeXML(skill.metadata.name))</name>")
            lines.append("    <description>\(escapeXML(skill.metadata.description))</description>")
            lines.append("    <location>\(escapeXML(skill.skillFilePath))</location>")
            lines.append("  </skill>")
        }

        lines.append("</available_skills>")

        return lines.joined(separator: "\n")
    }

    /// Generates full instructions for active skills.
    ///
    /// Used when injecting active skill context into prompts.
    ///
    /// - Returns: Combined instructions from all active skills.
    public func generateActiveSkillsPrompt() -> String {
        let activeList = activeSkillList

        guard !activeList.isEmpty else {
            return ""
        }

        var sections: [String] = []

        for skill in activeList {
            guard let instructions = skill.instructions else { continue }

            sections.append("""
                <active_skill name="\(escapeXML(skill.metadata.name))">
                \(instructions)
                </active_skill>
                """)
        }

        return sections.joined(separator: "\n\n")
    }

    // MARK: - Private Helpers

    /// Escapes special XML characters.
    private func escapeXML(_ string: String) -> String {
        string
            .replacingOccurrences(of: "&", with: "&amp;")
            .replacingOccurrences(of: "<", with: "&lt;")
            .replacingOccurrences(of: ">", with: "&gt;")
            .replacingOccurrences(of: "\"", with: "&quot;")
            .replacingOccurrences(of: "'", with: "&apos;")
    }
}

// MARK: - Convenience Extensions

extension SkillRegistry {

    /// Creates a registry by discovering skills from standard paths.
    ///
    /// - Parameter additionalPaths: Additional paths to search.
    /// - Returns: A registry with discovered skills.
    public static func discover(
        additionalPaths: [String] = []
    ) async throws -> SkillRegistry {
        let registry = SkillRegistry()

        // Discover from standard paths
        let standardSkills = try SkillDiscovery.discoverAll()
        await registry.register(standardSkills)

        // Discover from additional paths
        for path in additionalPaths {
            let skills = try SkillDiscovery.discover(in: path)
            await registry.register(skills)
        }

        return registry
    }
}
