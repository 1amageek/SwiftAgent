//
//  TestHelpers.swift
//  SwiftAgent
//
//  Shared test helpers for SwiftAgent tests.
//

import Foundation
import Testing
@testable import SwiftAgent

#if !USE_FOUNDATION_MODELS
import OpenFoundationModels

// MARK: - Mock Language Model

/// Mock LanguageModel for testing.
///
/// This mock returns a fixed response and tracks calls for verification.
struct TestMockLanguageModel: LanguageModel, Sendable {
    var id: String { "test-mock-model" }
    var isAvailable: Bool { true }

    func supports(locale: Locale) -> Bool { true }

    func generate(
        transcript: Transcript,
        options: GenerationOptions?
    ) async throws -> Transcript.Entry {
        .response(Transcript.Response(
            assetIDs: [],
            segments: [.text(Transcript.TextSegment(content: "Test mock response"))]
        ))
    }

    func stream(
        transcript: Transcript,
        options: GenerationOptions?
    ) -> AsyncThrowingStream<Transcript.Entry, Error> {
        AsyncThrowingStream { continuation in
            continuation.yield(.response(Transcript.Response(
                assetIDs: [],
                segments: [.text(Transcript.TextSegment(content: "Test mock response"))]
            )))
            continuation.finish()
        }
    }
}

// MARK: - Mock Model Provider

/// Mock ModelProvider for testing AgentSession configuration.
struct TestMockModelProvider: ModelProvider, Sendable {
    let modelID: String

    init(modelID: String = "test-mock-model") {
        self.modelID = modelID
    }

    func provideModel() async throws -> any LanguageModel {
        TestMockLanguageModel()
    }
}

// MARK: - Mock Tool

/// Mock Tool for testing tool configurations.
struct TestMockTool: Tool, Sendable {
    typealias Arguments = TestMockArguments
    typealias Output = String

    let name: String
    var description: String { "Test mock tool: \(name)" }
    var parameters: GenerationSchema { TestMockArguments.generationSchema }

    init(name: String = "test_mock_tool") {
        self.name = name
    }

    func call(arguments: TestMockArguments) async throws -> String {
        "Called \(name) with input: \(arguments.input)"
    }
}

/// Arguments for TestMockTool.
@Generable
struct TestMockArguments: Sendable {
    @Guide(description: "Test input parameter")
    let input: String
}

// MARK: - Mock Tool Provider

/// Mock ToolProvider for testing tool resolution.
struct TestMockToolProvider: ToolProvider, Sendable {
    let availableTools: [String: any Tool]

    init(tools: [any Tool] = []) {
        var dict: [String: any Tool] = [:]
        for tool in tools {
            dict[tool.name] = tool
        }
        self.availableTools = dict
    }

    func tools(for names: [String]) -> [any Tool] {
        names.compactMap { availableTools[$0] }
    }

    func tool(named name: String) -> (any Tool)? {
        availableTools[name]
    }
}

// MARK: - Configuration Factory

/// Factory for creating test configurations.
enum TestConfigurationFactory {

    /// Creates a minimal valid configuration for testing.
    static func minimal(
        instructions: String = "Test instructions",
        tools: ToolConfiguration = .disabled,
        workingDirectory: String = "/tmp"
    ) -> AgentConfiguration {
        AgentConfiguration(
            instructions: Instructions(instructions),
            tools: tools,
            modelProvider: TestMockModelProvider(),
            workingDirectory: workingDirectory
        )
    }

    /// Creates a configuration with custom tools.
    static func withTools(
        _ tools: [any Tool],
        instructions: String = "Test instructions",
        workingDirectory: String = "/tmp"
    ) -> AgentConfiguration {
        AgentConfiguration(
            instructions: Instructions(instructions),
            tools: .custom(tools),
            modelProvider: TestMockModelProvider(),
            workingDirectory: workingDirectory
        )
    }

    /// Creates a configuration with skills enabled.
    static func withSkills(
        tools: ToolConfiguration = .custom([TestMockTool()]),
        instructions: String = "Test instructions",
        workingDirectory: String = "/tmp"
    ) -> AgentConfiguration {
        AgentConfiguration(
            instructions: Instructions(instructions),
            tools: tools,
            modelProvider: TestMockModelProvider(),
            workingDirectory: workingDirectory,
            skills: .autoDiscover()
        )
    }

    /// Creates a configuration with context management.
    static func withContext(
        contextWindowSize: Int = 4096,
        compactionThreshold: Double = 0.8,
        enabled: Bool = true,
        instructions: String = "Test instructions",
        workingDirectory: String = "/tmp"
    ) -> AgentConfiguration {
        var contextConfig = ContextConfiguration(
            contextWindowSize: contextWindowSize,
            compactionThreshold: compactionThreshold
        )
        contextConfig.enabled = enabled

        return AgentConfiguration(
            instructions: Instructions(instructions),
            tools: .disabled,
            modelProvider: TestMockModelProvider(),
            workingDirectory: workingDirectory,
            context: contextConfig
        )
    }
}

#endif
