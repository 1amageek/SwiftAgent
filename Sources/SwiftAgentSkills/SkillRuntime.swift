//
//  SkillRuntime.swift
//  SwiftAgent
//

import Foundation
import SwiftAgent

/// Prepared runtime state for progressive skill disclosure.
///
/// `SkillRuntime` is a snapshot used when creating a model session. It exposes
/// only the skill catalog in initial instructions and registers `activate_skill`
/// so the model can request full instructions when needed.
public struct SkillRuntime: Sendable {
    public let registry: SkillRegistry
    public let permissions: SkillPermissions
    public let availableSkillsPrompt: String

    public init(
        registry: SkillRegistry,
        permissions: SkillPermissions = SkillPermissions(),
        availableSkillsPrompt: String
    ) {
        self.registry = registry
        self.permissions = permissions
        self.availableSkillsPrompt = availableSkillsPrompt
    }

    public var hasSkills: Bool {
        !availableSkillsPrompt.isEmpty
    }

    public var skillTool: SkillTool {
        SkillTool(registry: registry, permissions: permissions)
    }

    public var tools: [any Tool] {
        hasSkills ? [skillTool] : []
    }

    public var instructionsPrompt: String {
        guard hasSkills else {
            return ""
        }

        return """
        <skill_policy>
        Use available skills when they are relevant to the user's task.
        Do not assume a skill's full instructions from its name, description, or location.
        Before following a skill, call activate_skill with the skill name.
        After activation, follow the returned instructions.
        </skill_policy>

        \(availableSkillsPrompt)
        """
    }

    public var instructions: Instructions {
        Instructions(instructionsPrompt)
    }

    public func applying(
        to configuration: ToolRuntimeConfiguration
    ) -> ToolRuntimeConfiguration {
        configuration.withDynamicPermissions { permissions.rules }
    }

    public static func prepare(
        _ configuration: SkillsConfiguration = .autoDiscover(),
        cwd: String = FileManager.default.currentDirectoryPath,
        permissions: SkillPermissions = SkillPermissions()
    ) async throws -> SkillRuntime {
        let registry = configuration.registry ?? SkillRegistry()

        if configuration.autoDiscover {
            let discovered = try SkillDiscovery.discoverAll(cwd: cwd)
            await registry.register(discovered)
        }

        for path in configuration.searchPaths {
            let discovered = try SkillDiscovery.discover(in: path)
            await registry.register(discovered)
        }

        let prompt = await registry.generateAvailableSkillsPrompt()
        return SkillRuntime(
            registry: registry,
            permissions: permissions,
            availableSkillsPrompt: prompt
        )
    }
}
