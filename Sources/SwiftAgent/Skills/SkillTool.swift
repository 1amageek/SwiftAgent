//
//  SkillTool.swift
//  SwiftAgent
//
//  Created by SwiftAgent on 2025/01/15.
//

import Foundation

/// Tool for activating skills.
///
/// This tool allows the LLM to load a skill's full instructions
/// when it determines a skill is relevant to the current task.
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
/// let tool = SkillTool(registry: registry)
/// // Add to agent's tool set
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

    /// Creates a skill activation tool.
    ///
    /// - Parameter registry: The skill registry to activate skills from.
    public init(registry: SkillRegistry) {
        self.registry = registry
    }

    public func call(arguments: SkillToolArguments) async throws -> SkillToolOutput {
        let skill = try await registry.activate(arguments.skillName)

        return SkillToolOutput(
            skillName: skill.metadata.name,
            instructions: skill.instructions ?? "",
            hasScripts: skill.hasScripts,
            hasReferences: skill.hasReferences,
            hasAssets: skill.hasAssets,
            skillPath: skill.directoryPath
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

    public init(
        skillName: String,
        instructions: String,
        hasScripts: Bool,
        hasReferences: Bool,
        hasAssets: Bool,
        skillPath: String
    ) {
        self.skillName = skillName
        self.instructions = instructions
        self.hasScripts = hasScripts
        self.hasReferences = hasReferences
        self.hasAssets = hasAssets
        self.skillPath = skillPath
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

        return Prompt(sections.joined(separator: "\n"))
    }
}

// MARK: - CustomStringConvertible

extension SkillToolOutput: CustomStringConvertible {

    public var description: String {
        String(describing: promptRepresentation)
    }
}
