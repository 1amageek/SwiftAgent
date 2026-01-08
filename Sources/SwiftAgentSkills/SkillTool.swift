//
//  SkillTool.swift
//  SwiftAgent
//
//  Created by SwiftAgent on 2025/01/15.
//

import Foundation
import SwiftAgent

/// Tool for activating skills.
///
/// This tool allows the LLM to load a skill's full instructions
/// when it determines a skill is relevant to the current task.
///
/// When a skill is activated, its `allowed-tools` field (if present) is parsed
/// and the corresponding permission rules are added to the session's allow list.
///
/// ## Usage
///
/// The LLM sees available skills in `<available_skills>` XML and can
/// activate any skill by calling this tool with the skill name.
///
/// ```swift
/// let registry = SkillRegistry()
/// // ... register skills ...
///
/// // Without skill permissions (allowed-tools ignored)
/// let tool = SkillTool(registry: registry)
///
/// // With skill permissions (allowed-tools applied)
/// let permissions = SkillPermissions()
/// let tool = SkillTool(registry: registry, permissions: permissions)
/// ```
public struct SkillTool: Tool {

    public typealias Arguments = SkillToolArguments
    public typealias Output = SkillToolOutput

    public static let name = "activate_skill"
    public var name: String { Self.name }

    public static let toolDescription = """
        Activate a skill to load its full instructions into context.

        Use this when you determine a skill from <available_skills> is relevant
        to the current task. The skill's instructions will be returned and you
        should follow them to complete the task.

        Example: If the user asks about PDF processing and you see a "pdf-processing"
        skill in <available_skills>, activate it to get the detailed instructions.
        """

    public var description: String { Self.toolDescription }

    public var parameters: GenerationSchema {
        SkillToolArguments.generationSchema
    }

    private let registry: SkillRegistry
    private let permissions: SkillPermissions?

    /// Creates a skill activation tool.
    ///
    /// - Parameter registry: The skill registry to activate skills from.
    public init(registry: SkillRegistry) {
        self.registry = registry
        self.permissions = nil
    }

    /// Creates a skill activation tool with permission integration.
    ///
    /// When a skill is activated, its `allowed-tools` field is parsed and
    /// added to the `permissions` object, which is read by `PermissionMiddleware`.
    ///
    /// - Parameters:
    ///   - registry: The skill registry to activate skills from.
    ///   - permissions: The skill permissions container to add allowed tools to.
    public init(registry: SkillRegistry, permissions: SkillPermissions?) {
        self.registry = registry
        self.permissions = permissions
    }

    public func call(arguments: SkillToolArguments) async throws -> SkillToolOutput {
        let skill = try await registry.activate(arguments.skillName)

        // Parse and inject skill permissions if configured
        if let allowedToolsString = skill.metadata.allowedTools,
           let permissions = self.permissions {
            let rules = PermissionRule.parse(allowedToolsString)
            if !rules.isEmpty {
                permissions.add(rules, from: skill.metadata.name)
            }
        }

        return SkillToolOutput(
            skillName: skill.metadata.name,
            instructions: skill.instructions ?? "",
            hasScripts: skill.hasScripts,
            hasReferences: skill.hasReferences,
            hasAssets: skill.hasAssets,
            skillPath: skill.directoryPath,
            grantedPermissions: skill.metadata.allowedTools
        )
    }
}

// MARK: - Arguments

/// Arguments for the skill activation tool.
@Generable
public struct SkillToolArguments: Sendable {

    /// The name of the skill to activate.
    @Guide(description: "The name of the skill to activate, as shown in <available_skills>")
    public let skillName: String
}

// MARK: - Output

/// Output from the skill activation tool.
public struct SkillToolOutput: Sendable {

    /// The name of the activated skill.
    public let skillName: String

    /// The full instructions for the skill.
    public let instructions: String

    /// Whether the skill has a scripts directory.
    public let hasScripts: Bool

    /// Whether the skill has a references directory.
    public let hasReferences: Bool

    /// Whether the skill has an assets directory.
    public let hasAssets: Bool

    /// The path to the skill directory.
    public let skillPath: String

    /// The permission rules granted by this skill (if any).
    ///
    /// This is the raw `allowed-tools` string from the skill's SKILL.md.
    /// Example: `"Bash(git:*) Read Write"`
    public let grantedPermissions: String?

    public init(
        skillName: String,
        instructions: String,
        hasScripts: Bool,
        hasReferences: Bool,
        hasAssets: Bool,
        skillPath: String,
        grantedPermissions: String? = nil
    ) {
        self.skillName = skillName
        self.instructions = instructions
        self.hasScripts = hasScripts
        self.hasReferences = hasReferences
        self.hasAssets = hasAssets
        self.skillPath = skillPath
        self.grantedPermissions = grantedPermissions
    }
}

// MARK: - PromptRepresentable

extension SkillToolOutput: PromptRepresentable {

    public var promptRepresentation: Prompt {
        var sections: [String] = []

        sections.append("# Skill Activated: \(skillName)")
        sections.append("")
        sections.append(instructions)

        if hasScripts || hasReferences || hasAssets {
            sections.append("")
            sections.append("## Available Resources")
            sections.append("- Skill path: \(skillPath)")
            if hasScripts {
                sections.append("- Scripts: \(skillPath)/scripts/")
            }
            if hasReferences {
                sections.append("- References: \(skillPath)/references/")
            }
            if hasAssets {
                sections.append("- Assets: \(skillPath)/assets/")
            }
        }

        if let permissions = grantedPermissions, !permissions.isEmpty {
            sections.append("")
            sections.append("## Granted Permissions")
            sections.append("The following tools are pre-approved for this skill: \(permissions)")
        }

        return Prompt(sections.joined(separator: "\n"))
    }
}

// MARK: - CustomStringConvertible

extension SkillToolOutput: CustomStringConvertible {

    public var description: String {
        String(describing: promptRepresentation)
    }
}
