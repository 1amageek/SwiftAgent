//
//  AgentSession+Skills.swift
//  SwiftAgent
//

import Foundation
import SwiftAgent

extension AgentSession {
    #if OpenFoundationModels
    public func run<S: Step & Sendable>(
        model: any LanguageModel,
        tools: [any Tool] = [],
        skills: SkillRuntime,
        configuration: ToolRuntimeConfiguration = .default,
        @InstructionsBuilder instructions: @Sendable () -> Instructions,
        @StepBuilder step: @Sendable () -> S
    ) async throws where S.Input == Prompt, S.Output == String {
        var effectiveConfiguration = skills.applying(to: configuration)
        effectiveConfiguration.register(tools + skills.tools)
        let runtime = ToolRuntime(configuration: effectiveConfiguration)
        let languageModelSession = LanguageModelSession(model: model, tools: runtime.publicTools()) {
            Instructions {
                instructions()
                if skills.hasSkills {
                    skills.instructions
                }
            }
        }
        let conversation = Conversation(languageModelSession: languageModelSession, step: step)
        try await run(conversation)
    }

    public func run<S: Step & Sendable>(
        model: any LanguageModel,
        tools: [any Tool] = [],
        skills configuration: SkillsConfiguration = .autoDiscover(),
        cwd: String = FileManager.default.currentDirectoryPath,
        toolRuntimeConfiguration: ToolRuntimeConfiguration = .default,
        @InstructionsBuilder instructions: @Sendable () -> Instructions,
        @StepBuilder step: @Sendable () -> S
    ) async throws where S.Input == Prompt, S.Output == String {
        let runtime = try await SkillRuntime.prepare(configuration, cwd: cwd)
        try await run(
            model: model,
            tools: tools,
            skills: runtime,
            configuration: toolRuntimeConfiguration,
            instructions: instructions,
            step: step
        )
    }
    #else
    public func run<S: Step & Sendable>(
        tools: [any Tool] = [],
        skills: SkillRuntime,
        configuration: ToolRuntimeConfiguration = .default,
        @InstructionsBuilder instructions: @Sendable () -> Instructions,
        @StepBuilder step: @Sendable () -> S
    ) async throws where S.Input == Prompt, S.Output == String {
        var effectiveConfiguration = skills.applying(to: configuration)
        effectiveConfiguration.register(tools + skills.tools)
        let runtime = ToolRuntime(configuration: effectiveConfiguration)
        let languageModelSession = LanguageModelSession(tools: runtime.publicTools()) {
            Instructions {
                instructions()
                if skills.hasSkills {
                    skills.instructions
                }
            }
        }
        let conversation = Conversation(languageModelSession: languageModelSession, step: step)
        try await run(conversation)
    }

    public func run<S: Step & Sendable>(
        tools: [any Tool] = [],
        skills configuration: SkillsConfiguration = .autoDiscover(),
        cwd: String = FileManager.default.currentDirectoryPath,
        toolRuntimeConfiguration: ToolRuntimeConfiguration = .default,
        @InstructionsBuilder instructions: @Sendable () -> Instructions,
        @StepBuilder step: @Sendable () -> S
    ) async throws where S.Input == Prompt, S.Output == String {
        let runtime = try await SkillRuntime.prepare(configuration, cwd: cwd)
        try await run(
            tools: tools,
            skills: runtime,
            configuration: toolRuntimeConfiguration,
            instructions: instructions,
            step: step
        )
    }
    #endif
}
