//
//  AgentSession+SwiftAgentPlugins.swift
//  SwiftAgentPlugins
//

import Foundation
import SwiftAgent

extension AgentSession {
    #if OpenFoundationModels
    public func run<S: Step & Sendable>(
        model: any LanguageModel,
        tools: [any Tool] = [],
        pluginRegistry: PluginRegistry? = nil,
        configuration: ToolRuntimeConfiguration = .default,
        @InstructionsBuilder instructions: @Sendable () -> Instructions,
        @StepBuilder step: @Sendable () -> S
    ) async throws where S.Input == Prompt, S.Output == String {
        var effectiveConfiguration = configuration
        if let pluginRegistry {
            effectiveConfiguration = try effectiveConfiguration.withPluginRegistry(pluginRegistry)
            effectiveConfiguration.register(tools + (try pluginRegistry.aggregatedSwiftAgentTools()))
        } else {
            effectiveConfiguration.register(tools)
        }
        let runtime = ToolRuntime(configuration: effectiveConfiguration)
        let languageModelSession = LanguageModelSession(model: model, tools: runtime.publicTools()) {
            instructions()
        }
        let conversation = Conversation(languageModelSession: languageModelSession, step: step)
        try await run(conversation)
    }
    #else
    public func run<S: Step & Sendable>(
        tools: [any Tool] = [],
        pluginRegistry: PluginRegistry? = nil,
        configuration: ToolRuntimeConfiguration = .default,
        @InstructionsBuilder instructions: @Sendable () -> Instructions,
        @StepBuilder step: @Sendable () -> S
    ) async throws where S.Input == Prompt, S.Output == String {
        var effectiveConfiguration = configuration
        if let pluginRegistry {
            effectiveConfiguration = try effectiveConfiguration.withPluginRegistry(pluginRegistry)
            effectiveConfiguration.register(tools + (try pluginRegistry.aggregatedSwiftAgentTools()))
        } else {
            effectiveConfiguration.register(tools)
        }
        let runtime = ToolRuntime(configuration: effectiveConfiguration)
        let languageModelSession = LanguageModelSession(tools: runtime.publicTools()) {
            instructions()
        }
        let conversation = Conversation(languageModelSession: languageModelSession, step: step)
        try await run(conversation)
    }
    #endif
}
