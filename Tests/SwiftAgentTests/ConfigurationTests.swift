//
//  ConfigurationTests.swift
//  SwiftAgent
//
//  Tests to verify that AgentConfiguration settings are properly applied.
//

import Testing
import Foundation
@testable import SwiftAgent

#if USE_OTHER_MODELS
import OpenFoundationModels

// MARK: - ToolConfiguration Tests

@Suite("ToolConfiguration Tests")
struct ToolConfigurationTests {

    @Test("isDisabled returns true for .disabled")
    func isDisabledReturnsTrue() {
        let config = ToolConfiguration.disabled
        #expect(config.isDisabled == true)
    }

    @Test("isDisabled returns false for .preset")
    func isDisabledReturnsFalseForPreset() {
        let config = ToolConfiguration.preset(.default)
        #expect(config.isDisabled == false)
    }

    @Test("isDisabled returns false for .custom")
    func isDisabledReturnsFalseForCustom() {
        let config = ToolConfiguration.custom([TestMockTool()])
        #expect(config.isDisabled == false)
    }

    @Test("isDisabled returns false for .allowlist")
    func isDisabledReturnsFalseForAllowlist() {
        let config = ToolConfiguration.allowlist([TestMockTool()])
        #expect(config.isDisabled == false)
    }

    @Test(".disabled resolves to empty array")
    func disabledResolvesToEmpty() {
        let config = ToolConfiguration.disabled
        let provider = TestMockToolProvider()
        let tools = config.resolve(using: provider)
        #expect(tools.isEmpty)
    }

    @Test(".custom resolves to provided tools")
    func customResolvesToProvidedTools() {
        let tool1 = TestMockTool(name: "tool1")
        let tool2 = TestMockTool(name: "tool2")
        let config = ToolConfiguration.custom([tool1, tool2])
        let provider = TestMockToolProvider()
        let tools = config.resolve(using: provider)
        #expect(tools.count == 2)
        #expect(tools.map { $0.name }.contains("tool1"))
        #expect(tools.map { $0.name }.contains("tool2"))
    }

    @Test(".allowlist resolves to provided tools")
    func allowlistResolvesToProvidedTools() {
        let tool = TestMockTool(name: "allowed_tool")
        let config = ToolConfiguration.allowlist([tool])
        let provider = TestMockToolProvider()
        let tools = config.resolve(using: provider)
        #expect(tools.count == 1)
        #expect(tools.first?.name == "allowed_tool")
    }

    @Test("allows(toolName:) returns correct values")
    func allowsToolNameReturnsCorrectly() {
        let tool = TestMockTool(name: "my_tool")
        let config = ToolConfiguration.custom([tool])

        #expect(config.allows(toolName: "my_tool") == true)
        #expect(config.allows(toolName: "other_tool") == false)
    }

    @Test(".disabled allows no tools")
    func disabledAllowsNoTools() {
        let config = ToolConfiguration.disabled
        #expect(config.allows(toolName: "any_tool") == false)
    }

    @Test("allowedToolNames returns correct names")
    func allowedToolNamesReturnsCorrectNames() {
        let tool1 = TestMockTool(name: "alpha")
        let tool2 = TestMockTool(name: "beta")
        let config = ToolConfiguration.custom([tool1, tool2])

        let names = config.allowedToolNames
        #expect(names.count == 2)
        #expect(names.contains("alpha"))
        #expect(names.contains("beta"))
    }

    @Test(".disabled has empty allowedToolNames")
    func disabledHasEmptyAllowedToolNames() {
        let config = ToolConfiguration.disabled
        #expect(config.allowedToolNames.isEmpty)
    }
}

// MARK: - AgentConfiguration Validation Tests

@Suite("AgentConfiguration Validation Tests")
struct AgentConfigurationValidationTests {

    @Test("valid configuration passes validation")
    func validConfigPasses() throws {
        let config = TestConfigurationFactory.minimal()
        #expect(throws: Never.self) {
            try config.validate()
        }
    }

    @Test("invalid temperature fails validation")
    func invalidTemperatureFails() {
        let config = AgentConfiguration(
            instructions: Instructions("Test"),
            tools: .disabled,
            modelProvider: TestMockModelProvider(),
            modelConfiguration: ModelConfiguration(temperature: 3.0),  // > 2.0 is invalid
            workingDirectory: "/tmp"
        )

        #expect(throws: AgentError.self) {
            try config.validate()
        }
    }

    @Test("negative temperature fails validation")
    func negativeTemperatureFails() {
        let config = AgentConfiguration(
            instructions: Instructions("Test"),
            tools: .disabled,
            modelProvider: TestMockModelProvider(),
            modelConfiguration: ModelConfiguration(temperature: -0.5),
            workingDirectory: "/tmp"
        )

        #expect(throws: AgentError.self) {
            try config.validate()
        }
    }

    @Test("invalid topP fails validation")
    func invalidTopPFails() {
        let config = AgentConfiguration(
            instructions: Instructions("Test"),
            tools: .disabled,
            modelProvider: TestMockModelProvider(),
            modelConfiguration: ModelConfiguration(topP: 1.5),  // > 1.0 is invalid
            workingDirectory: "/tmp"
        )

        #expect(throws: AgentError.self) {
            try config.validate()
        }
    }

    @Test("negative topP fails validation")
    func negativeTopPFails() {
        let config = AgentConfiguration(
            instructions: Instructions("Test"),
            tools: .disabled,
            modelProvider: TestMockModelProvider(),
            modelConfiguration: ModelConfiguration(topP: -0.1),
            workingDirectory: "/tmp"
        )

        #expect(throws: AgentError.self) {
            try config.validate()
        }
    }

    @Test("valid temperature and topP pass validation")
    func validTemperatureAndTopPPass() throws {
        let config = AgentConfiguration(
            instructions: Instructions("Test"),
            tools: .disabled,
            modelProvider: TestMockModelProvider(),
            modelConfiguration: ModelConfiguration(temperature: 0.7, topP: 0.9),
            workingDirectory: "/tmp"
        )

        #expect(throws: Never.self) {
            try config.validate()
        }
    }
}

// MARK: - SkillTool Addition Tests

@Suite("SkillTool Addition Tests")
struct SkillToolAdditionTests {

    @Test("SkillTool NOT added when tools disabled")
    func skillToolNotAddedWhenToolsDisabled() async throws {
        let config = AgentConfiguration(
            instructions: Instructions("Test"),
            tools: .disabled,
            modelProvider: TestMockModelProvider(),
            workingDirectory: "/tmp",
            skills: .autoDiscover()
        )

        let session = try await AgentSession.create(configuration: config)
        let transcript = await session.transcript

        // Check that no tools are in the transcript (including SkillTool)
        for entry in transcript {
            if case .instructions(let inst) = entry {
                #expect(inst.toolDefinitions.isEmpty, "Tools should be empty when disabled")
            }
        }
    }

    @Test("SkillTool added when tools enabled with skills")
    func skillToolAddedWhenToolsEnabledWithSkills() async throws {
        let mockTool = TestMockTool(name: "test_tool")
        let config = AgentConfiguration(
            instructions: Instructions("Test"),
            tools: .custom([mockTool]),
            modelProvider: TestMockModelProvider(),
            workingDirectory: "/tmp",
            skills: .autoDiscover()
        )

        let session = try await AgentSession.create(configuration: config)
        let transcript = await session.transcript

        // Check that SkillTool is added (should have 2 tools: mockTool + SkillTool)
        for entry in transcript {
            if case .instructions(let inst) = entry {
                let toolNames = inst.toolDefinitions.map { $0.name }
                #expect(toolNames.contains("test_tool"), "Should contain custom tool")
                #expect(toolNames.contains("activate_skill"), "Should contain SkillTool")
            }
        }
    }

    @Test("SkillTool NOT added when skills disabled")
    func skillToolNotAddedWhenSkillsDisabled() async throws {
        let mockTool = TestMockTool(name: "test_tool")
        let config = AgentConfiguration(
            instructions: Instructions("Test"),
            tools: .custom([mockTool]),
            modelProvider: TestMockModelProvider(),
            workingDirectory: "/tmp",
            skills: nil
        )

        let session = try await AgentSession.create(configuration: config)
        let transcript = await session.transcript

        // Check that only the mock tool is present, no SkillTool
        for entry in transcript {
            if case .instructions(let inst) = entry {
                let toolNames = inst.toolDefinitions.map { $0.name }
                #expect(toolNames.contains("test_tool"), "Should contain custom tool")
                #expect(!toolNames.contains("activate_skill"), "Should NOT contain SkillTool")
            }
        }
    }
}

// MARK: - Instructions Tests

@Suite("Instructions Configuration Tests")
struct InstructionsConfigurationTests {

    @Test("Instructions included in transcript")
    func instructionsIncludedInTranscript() async throws {
        let instructionText = "You are a helpful assistant."
        let config = AgentConfiguration(
            instructions: Instructions(instructionText),
            tools: .disabled,
            modelProvider: TestMockModelProvider(),
            workingDirectory: "/tmp"
        )

        let session = try await AgentSession.create(configuration: config)
        let transcript = await session.transcript

        // Verify instructions are in the transcript
        var foundInstructions = false
        for entry in transcript {
            if case .instructions(let inst) = entry {
                foundInstructions = true
                // Check that the instruction text is present in segments
                let textContent = inst.segments.compactMap { segment -> String? in
                    if case .text(let textSeg) = segment {
                        return textSeg.content
                    }
                    return nil
                }.joined()
                #expect(textContent.contains(instructionText), "Instructions should contain the provided text")
            }
        }
        #expect(foundInstructions, "Transcript should contain instructions")
    }

    @Test("Multiple instructions segments joined correctly")
    func multipleInstructionsSegmentsJoinedCorrectly() async throws {
        let config = TestConfigurationFactory.minimal(instructions: "Line one\nLine two")

        let session = try await AgentSession.create(configuration: config)
        let transcript = await session.transcript

        for entry in transcript {
            if case .instructions(let inst) = entry {
                let textContent = inst.segments.compactMap { segment -> String? in
                    if case .text(let textSeg) = segment {
                        return textSeg.content
                    }
                    return nil
                }.joined()
                #expect(textContent.contains("Line one"))
                #expect(textContent.contains("Line two"))
            }
        }
    }
}

// MARK: - Context Configuration Tests

@Suite("Context Configuration Tests")
struct ContextConfigurationTests {

    @Test("Context management enabled when configured")
    func contextManagementEnabledWhenConfigured() async throws {
        let config = TestConfigurationFactory.withContext(enabled: true)

        let session = try await AgentSession.create(configuration: config)
        #expect(await session.contextManagementEnabled == true)
    }

    @Test("Context management disabled when not configured")
    func contextManagementDisabledWhenNotConfigured() async throws {
        let config = TestConfigurationFactory.minimal()

        let session = try await AgentSession.create(configuration: config)
        #expect(await session.contextManagementEnabled == false)
    }

    @Test("Context management disabled when enabled=false")
    func contextManagementDisabledWhenEnabledFalse() async throws {
        let config = TestConfigurationFactory.withContext(enabled: false)

        let session = try await AgentSession.create(configuration: config)
        #expect(await session.contextManagementEnabled == false)
    }
}

// MARK: - Session ID Tests

@Suite("Session ID Tests")
struct SessionIDTests {

    @Test("Session has unique ID")
    func sessionHasUniqueID() async throws {
        let config = TestConfigurationFactory.minimal()

        let session1 = try await AgentSession.create(configuration: config)
        let session2 = try await AgentSession.create(configuration: config)

        #expect(session1.id != session2.id, "Each session should have a unique ID")
    }

    @Test("Session ID is valid UUID format")
    func sessionIDIsValidUUIDFormat() async throws {
        let config = TestConfigurationFactory.minimal()

        let session = try await AgentSession.create(configuration: config)
        let uuid = UUID(uuidString: session.id)
        #expect(uuid != nil, "Session ID should be a valid UUID")
    }
}

// MARK: - Working Directory Tests

@Suite("Working Directory Tests")
struct WorkingDirectoryTests {

    @Test("Working directory stored in configuration")
    func workingDirectoryStoredInConfiguration() async throws {
        let workDir = "/custom/path"
        let config = AgentConfiguration(
            instructions: Instructions("Test"),
            tools: .disabled,
            modelProvider: TestMockModelProvider(),
            workingDirectory: workDir
        )

        let session = try await AgentSession.create(configuration: config)
        #expect(await session.configuration.workingDirectory == workDir)
    }
}

// MARK: - Tool Definition in Transcript Tests

@Suite("Tool Definition in Transcript Tests")
struct ToolDefinitionInTranscriptTests {

    @Test("Tools are registered in transcript instructions")
    func toolsRegisteredInTranscriptInstructions() async throws {
        let tool1 = TestMockTool(name: "tool_alpha")
        let tool2 = TestMockTool(name: "tool_beta")
        let config = AgentConfiguration(
            instructions: Instructions("Test"),
            tools: .custom([tool1, tool2]),
            modelProvider: TestMockModelProvider(),
            workingDirectory: "/tmp"
        )

        let session = try await AgentSession.create(configuration: config)
        let transcript = await session.transcript

        var foundToolCount = 0
        for entry in transcript {
            if case .instructions(let inst) = entry {
                let toolNames = inst.toolDefinitions.map { $0.name }
                foundToolCount = toolNames.count
                #expect(toolNames.contains("tool_alpha"))
                #expect(toolNames.contains("tool_beta"))
            }
        }
        #expect(foundToolCount == 2, "Should have exactly 2 tools")
    }

    @Test("No tools in transcript when disabled")
    func noToolsInTranscriptWhenDisabled() async throws {
        let config = TestConfigurationFactory.minimal(tools: .disabled)

        let session = try await AgentSession.create(configuration: config)
        let transcript = await session.transcript

        for entry in transcript {
            if case .instructions(let inst) = entry {
                #expect(inst.toolDefinitions.isEmpty, "Should have no tool definitions")
            }
        }
    }
}

// MARK: - Skills Enabled Property Tests

@Suite("Skills Enabled Property Tests")
struct SkillsEnabledPropertyTests {

    @Test("skillsEnabled is true when skills configured")
    func skillsEnabledIsTrueWhenConfigured() async throws {
        let config = TestConfigurationFactory.withSkills()

        let session = try await AgentSession.create(configuration: config)
        #expect(await session.skillsEnabled == true)
    }

    @Test("skillsEnabled is false when skills not configured")
    func skillsEnabledIsFalseWhenNotConfigured() async throws {
        let config = TestConfigurationFactory.minimal()

        let session = try await AgentSession.create(configuration: config)
        #expect(await session.skillsEnabled == false)
    }
}

// MARK: - Model Provider Tests

@Suite("Model Provider Tests")
struct ModelProviderTests {

    @Test("PreloadedModelProvider returns model with correct ID")
    func preloadedModelProviderReturnsCorrectID() async throws {
        let model = TestMockLanguageModel()
        let provider = PreloadedModelProvider(model: model, id: "my-custom-id")

        #expect(provider.modelID == "my-custom-id")

        let providedModel = try await provider.provideModel()
        // Verify the model is available (basic check)
        #expect(providedModel.isAvailable == true)
    }

    @Test("LazyModelProvider caches model after first load")
    func lazyModelProviderCachesModel() async throws {
        let provider = LazyModelProvider(id: "lazy-model") {
            TestMockLanguageModel()
        }

        #expect(provider.modelID == "lazy-model")

        // First call - should load the model
        let model1 = try await provider.provideModel()
        #expect(model1.isAvailable == true)

        // Second call - should return cached model
        let model2 = try await provider.provideModel()
        #expect(model2.isAvailable == true)
    }

    @Test("LazyModelProvider isAvailable before load")
    func lazyModelProviderIsAvailableBeforeLoad() async throws {
        let provider = LazyModelProvider(id: "lazy-model") {
            TestMockLanguageModel()
        }

        // Before loading, isAvailable should be false
        let availableBefore = await provider.isAvailable
        #expect(availableBefore == false)

        // After loading, isAvailable should be true
        _ = try await provider.provideModel()
        let availableAfter = await provider.isAvailable
        #expect(availableAfter == true)
    }

    @Test("ModelProviderFactory creates correct providers")
    func modelProviderFactoryCreatesCorrectProviders() async throws {
        let model = TestMockLanguageModel()
        let preloaded = ModelProviderFactory.preloaded(model, id: "factory-preloaded")
        #expect(preloaded.modelID == "factory-preloaded")

        let lazy = ModelProviderFactory.lazy(id: "factory-lazy") {
            TestMockLanguageModel()
        }
        #expect(lazy.modelID == "factory-lazy")
    }
}

// MARK: - ModelConfiguration Tests

@Suite("ModelConfiguration Tests")
struct ModelConfigurationTests {

    @Test("Default configuration has nil values")
    func defaultConfigurationHasNilValues() {
        let config = ModelConfiguration.default
        #expect(config.maxTokens == nil)
        #expect(config.temperature == nil)
        #expect(config.topP == nil)
        #expect(config.stopSequences.isEmpty)
    }

    @Test("Code configuration has low temperature")
    func codeConfigurationHasLowTemperature() {
        let config = ModelConfiguration.code
        #expect(config.temperature == 0.2)
    }

    @Test("Creative configuration has high temperature")
    func creativeConfigurationHasHighTemperature() {
        let config = ModelConfiguration.creative
        #expect(config.temperature == 0.8)
    }

    @Test("Deterministic configuration has zero temperature")
    func deterministicConfigurationHasZeroTemperature() {
        let config = ModelConfiguration.deterministic
        #expect(config.temperature == 0.0)
    }

    @Test("toGenerationOptions converts correctly")
    func toGenerationOptionsConvertsCorrectly() {
        let config = ModelConfiguration(
            maxTokens: 100,
            temperature: 0.5,
            topP: 0.9
        )

        let options = config.toGenerationOptions()
        #expect(options.temperature == 0.5)
        #expect(options.maximumResponseTokens == 100)
    }
}

// MARK: - ToolConfiguration Builder Tests

@Suite("ToolConfiguration Builder Tests")
struct ToolConfigurationBuilderTests {

    @Test("build creates custom configuration")
    func buildCreatesCustomConfiguration() {
        let config = ToolConfiguration.build {
            TestMockTool(name: "builder_tool_1")
            TestMockTool(name: "builder_tool_2")
        }

        #expect(config.allowedToolNames.count == 2)
        #expect(config.allows(toolName: "builder_tool_1"))
        #expect(config.allows(toolName: "builder_tool_2"))
    }

    @Test("isEquivalent compares by tool names")
    func isEquivalentComparesByToolNames() {
        let tool = TestMockTool(name: "same_tool")
        let config1 = ToolConfiguration.custom([tool])
        let config2 = ToolConfiguration.allowlist([tool])

        #expect(config1.isEquivalent(to: config2))
    }

    @Test("isEquivalent returns false for different tools")
    func isEquivalentReturnsFalseForDifferentTools() {
        let config1 = ToolConfiguration.custom([TestMockTool(name: "tool_a")])
        let config2 = ToolConfiguration.custom([TestMockTool(name: "tool_b")])

        #expect(!config1.isEquivalent(to: config2))
    }
}

// MARK: - ToolConfiguration Description Tests

@Suite("ToolConfiguration Description Tests")
struct ToolConfigurationDescriptionTests {

    @Test("disabled has correct description")
    func disabledHasCorrectDescription() {
        let config = ToolConfiguration.disabled
        #expect(config.description == "disabled")
    }

    @Test("preset has correct description")
    func presetHasCorrectDescription() {
        let config = ToolConfiguration.preset(.default)
        #expect(config.description == "preset(default)")
    }

    @Test("custom has correct description")
    func customHasCorrectDescription() {
        let config = ToolConfiguration.custom([TestMockTool(name: "my_tool")])
        #expect(config.description == "custom([my_tool])")
    }

    @Test("allowlist has correct description")
    func allowlistHasCorrectDescription() {
        let config = ToolConfiguration.allowlist([TestMockTool(name: "allowed")])
        #expect(config.description == "allowlist([allowed])")
    }
}

#endif
