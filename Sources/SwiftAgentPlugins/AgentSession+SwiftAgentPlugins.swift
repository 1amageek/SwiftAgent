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
        pipeline: ToolPipeline = .default,
        @InstructionsBuilder instructions: @Sendable () -> Instructions,
        @StepBuilder step: @Sendable () -> S
    ) async throws where S.Input == Prompt, S.Output == String {
        let effectivePipeline: ToolPipeline
        let effectiveTools: [any Tool]
        if let pluginRegistry {
            effectivePipeline = try pipeline.withPluginRegistry(pluginRegistry)
            effectiveTools = tools + (try pluginRegistry.aggregatedSwiftAgentTools())
        } else {
            effectivePipeline = pipeline
            effectiveTools = tools
        }
        let wrappedTools = effectivePipeline.wrap(effectiveTools)
        let languageModelSession = LanguageModelSession(model: model, tools: wrappedTools) {
            instructions()
        }
        let conversation = Conversation(languageModelSession: languageModelSession, step: step)
        try await run(conversation)
    }
    #else
    public func run<S: Step & Sendable>(
        tools: [any Tool] = [],
        pluginRegistry: PluginRegistry? = nil,
        pipeline: ToolPipeline = .default,
        @InstructionsBuilder instructions: @Sendable () -> Instructions,
        @StepBuilder step: @Sendable () -> S
    ) async throws where S.Input == Prompt, S.Output == String {
        let effectivePipeline: ToolPipeline
        let effectiveTools: [any Tool]
        if let pluginRegistry {
            effectivePipeline = try pipeline.withPluginRegistry(pluginRegistry)
            effectiveTools = tools + (try pluginRegistry.aggregatedSwiftAgentTools())
        } else {
            effectivePipeline = pipeline
            effectiveTools = tools
        }
        let wrappedTools = effectivePipeline.wrap(effectiveTools)
        let languageModelSession = LanguageModelSession(tools: wrappedTools) {
            instructions()
        }
        let conversation = Conversation(languageModelSession: languageModelSession, step: step)
        try await run(conversation)
    }
    #endif
}
