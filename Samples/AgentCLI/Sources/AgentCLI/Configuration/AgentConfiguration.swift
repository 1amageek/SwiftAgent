//
//  AgentConfiguration.swift
//  AgentCLI
//
//  Created by SwiftAgent on 2025/01/17.
//

import Foundation
import SwiftAgent
import OpenFoundationModelsOpenAI

/// Configuration for agent setup
public struct AgentConfiguration: Sendable {

    /// OpenAI API key
    public let apiKey: String

    /// Model to use
    public let model: OpenAIModel

    /// Enable verbose logging
    public let verbose: Bool

    /// Working directory for file operations
    public let workingDirectory: String

    public init(
        apiKey: String,
        model: OpenAIModel = .gpt41,
        verbose: Bool = false,
        workingDirectory: String = FileManager.default.currentDirectoryPath
    ) {
        self.apiKey = apiKey
        self.model = model
        self.verbose = verbose
        self.workingDirectory = workingDirectory
    }

    /// Creates an OpenAI language model instance
    public func createModel() -> OpenAILanguageModel {
        let config = OpenAIConfiguration(apiKey: apiKey)
        return OpenAILanguageModel(configuration: config, model: model)
    }

    /// Creates a LanguageModelSession with the specified tools and instructions
    public func createSession(
        tools: [any OpenFoundationModels.Tool] = [],
        instructions: Instructions
    ) -> LanguageModelSession {
        LanguageModelSession(
            model: createModel(),
            tools: tools,
            instructions: instructions
        )
    }
}
