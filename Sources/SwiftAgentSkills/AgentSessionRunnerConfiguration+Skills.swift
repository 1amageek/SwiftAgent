//
//  AgentSessionRunnerConfiguration+Skills.swift
//  SwiftAgent
//

import Foundation
import SwiftAgent

extension AgentSessionRunnerConfiguration {
    public init<S: Step & Sendable>(
        tools: [any Tool] = [],
        skills: SkillRuntime,
        runtimeConfiguration: ToolRuntimeConfiguration = .default,
        approvalHandler: (any ApprovalHandler)? = nil,
        eventHandler: (@Sendable (AgentTaskEvent) async -> Void)? = nil,
        @InstructionsBuilder instructions: @escaping @Sendable () -> Instructions,
        @StepBuilder step: @escaping @Sendable () -> S
    ) where S.Input == Prompt, S.Output == String {
        self.init(
            tools: tools + skills.tools,
            runtimeConfiguration: skills.applying(to: runtimeConfiguration),
            approvalHandler: approvalHandler,
            eventHandler: eventHandler
        ) {
            Instructions {
                instructions()
                if skills.hasSkills {
                    skills.instructions
                }
            }
        } step: {
            step()
        }
    }

    public static func withSkills<S: Step & Sendable>(
        tools: [any Tool] = [],
        skills configuration: SkillsConfiguration = .autoDiscover(),
        cwd: String = FileManager.default.currentDirectoryPath,
        runtimeConfiguration: ToolRuntimeConfiguration = .default,
        approvalHandler: (any ApprovalHandler)? = nil,
        eventHandler: (@Sendable (AgentTaskEvent) async -> Void)? = nil,
        @InstructionsBuilder instructions: @escaping @Sendable () -> Instructions,
        @StepBuilder step: @escaping @Sendable () -> S
    ) async throws -> AgentSessionRunnerConfiguration where S.Input == Prompt, S.Output == String {
        let runtime = try await SkillRuntime.prepare(configuration, cwd: cwd)
        return AgentSessionRunnerConfiguration(
            tools: tools,
            skills: runtime,
            runtimeConfiguration: runtimeConfiguration,
            approvalHandler: approvalHandler,
            eventHandler: eventHandler,
            instructions: instructions,
            step: step
        )
    }
}
