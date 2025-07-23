//
//  ToolCompatibilityTests.swift
//  SwiftAgent
//
//  Created by Norikazu Muramoto on 2025/01/16.
//

import Testing
@testable import Agents
@testable import SwiftAgent
@testable import AgentTools
@testable import OpenFoundationModels

@Suite("Tool Compatibility Tests")
struct ToolCompatibilityTests {
    
    @Test("SwiftAgent Tool to Model Tool Conversion")
    func swiftAgentToModelToolConversion() async throws {
        let mockTool = MockSwiftAgentTool()
        let modelTool = ToolAdapter(mockTool)
        
        #expect(modelTool.name == mockTool.name)
        #expect(modelTool.description == mockTool.description)
        
        let input = MockToolInput(value: "test")
        let result = try await modelTool.call(input)
        #expect(result == "Mock output: test")
    }
    
    @Test("Model Tool to SwiftAgent Tool Conversion")
    func modelToSwiftAgentToolConversion() async throws {
        let mockModelTool = MockModelTool()
        let swiftAgentTool = ModelToolWrapper<String, String>(mockModelTool)
        
        #expect(swiftAgentTool.name == mockModelTool.name)
        #expect(swiftAgentTool.description == mockModelTool.description)
        
        let result = try await swiftAgentTool.run("test input")
        #expect(result == "Model mock response: test input")
    }
    
    @Test("Tool Array Conversion - SwiftAgent to Model")
    func toolArrayConversionSwiftAgentToModel() async throws {
        let swiftAgentTools: [any SwiftAgent.Tool] = [
            MockSwiftAgentTool(name: "tool1"),
            MockSwiftAgentTool(name: "tool2")
        ]
        
        let modelTools = swiftAgentTools.toModelTools()
        #expect(modelTools.count == 2)
        #expect(modelTools[0].name == "tool1")
        #expect(modelTools[1].name == "tool2")
    }
    
    @Test("Tool Array Conversion - Model to SwiftAgent")
    func toolArrayConversionModelToSwiftAgent() async throws {
        let modelTools: [any OpenFoundationModels.Tool] = [
            MockModelTool(name: "model_tool1"),
            MockModelTool(name: "model_tool2")
        ]
        
        let swiftAgentTools: [ModelToolWrapper<String, String>] = modelTools.toSwiftAgentTools()
        #expect(swiftAgentTools.count == 2)
        #expect(swiftAgentTools[0].name == "model_tool1")
        #expect(swiftAgentTools[1].name == "model_tool2")
    }
    
    @Test("Real AgentTools Compatibility")
    func realAgentToolsCompatibility() async throws {
        // Test with real AgentTools
        let fileSystemTool = FileSystemTool(workingDirectory: "/tmp")
        let modelWrapper = ToolAdapter(fileSystemTool)
        
        #expect(modelWrapper.name == fileSystemTool.name)
        #expect(modelWrapper.description == fileSystemTool.description)
        
        // Test tool execution with valid input
        // Note: This test might need to be adapted based on actual FileSystemTool input/output types
    }
    
    @Test("ExecuteCommandTool Compatibility")
    func executeCommandToolCompatibility() async throws {
        let executeCommandTool = ExecuteCommandTool()
        let modelWrapper = ToolAdapter(executeCommandTool)
        
        #expect(modelWrapper.name == executeCommandTool.name)
        #expect(modelWrapper.description == executeCommandTool.description)
        
        // Test that the tool maintains its functionality when wrapped
        #expect(modelWrapper.parameters == executeCommandTool.parameters)
    }
    
    @Test("URLFetchTool Compatibility")
    func urlFetchToolCompatibility() async throws {
        let urlFetchTool = URLFetchTool()
        let modelWrapper = ToolAdapter(urlFetchTool)
        
        #expect(modelWrapper.name == urlFetchTool.name)
        #expect(modelWrapper.description == urlFetchTool.description)
        #expect(modelWrapper.parameters == urlFetchTool.parameters)
    }
    
    @Test("GitTool Compatibility")
    func gitToolCompatibility() async throws {
        let gitTool = GitTool()
        let modelWrapper = ToolAdapter(gitTool)
        
        #expect(modelWrapper.name == gitTool.name)
        #expect(modelWrapper.description == gitTool.description)
        #expect(modelWrapper.parameters == gitTool.parameters)
    }
    
    @Test("Tool Manager Conversion Functions")
    func toolManagerConversionFunctions() async throws {
        let swiftAgentTools: [any SwiftAgent.Tool] = [MockSwiftAgentTool()]
        let modelTools = ToolManager.convert(swiftAgentTools)
        
        #expect(modelTools.count == 1)
        #expect(modelTools[0].name == "mock_tool")
        
        let backToSwiftAgent = ToolManager.convert(modelTools)
        #expect(backToSwiftAgent.count == 1)
        #expect(backToSwiftAgent[0].name == "mock_tool")
    }
    
    @Test("Tool Error Handling")
    func toolErrorHandling() async throws {
        let errorTool = ErrorThrowingTool()
        let modelWrapper = ToolAdapter(errorTool)
        
        do {
            _ = try await modelWrapper.call(MockToolInput(value: "error"))
            Issue.record("Expected error to be thrown")
        } catch {
            // Error should be caught and converted to string result
            #expect(error is ToolError)
        }
    }
}

// MARK: - Mock Implementations for Testing

private struct MockSwiftAgentTool: SwiftAgent.Tool {
    typealias Input = MockToolInput
    typealias Output = MockToolOutput
    
    let name: String
    let description = "A mock tool for testing"
    let parameters = JSONSchema.object([
        "value": .string
    ])
    let guide: String? = nil
    
    init(name: String = "mock_tool") {
        self.name = name
    }
    
    func run(_ input: MockToolInput) async throws -> MockToolOutput {
        return MockToolOutput(result: "Mock output: \(input.value)")
    }
}

private struct MockModelTool: OpenFoundationModels.Tool {
    let name: String
    let description = "A mock model tool"
    let parameters = JSONSchema.object([
        "input": .string
    ])
    let guide: String? = nil
    
    init(name: String = "model_mock_tool") {
        self.name = name
    }
    
    func call(_ arguments: any Encodable) async throws -> String {
        if let input = arguments as? String {
            return "Model mock response: \(input)"
        }
        return "Model mock response: unknown input"
    }
}

private struct ErrorThrowingTool: SwiftAgent.Tool {
    typealias Input = MockToolInput
    typealias Output = MockToolOutput
    
    let name = "error_tool"
    let description = "A tool that throws errors"
    let parameters = JSONSchema.object([
        "value": .string
    ])
    let guide: String? = nil
    
    func run(_ input: MockToolInput) async throws -> MockToolOutput {
        if input.value == "error" {
            throw ToolError.executionFailed("Intentional test error")
        }
        return MockToolOutput(result: "No error")
    }
}

private struct MockToolInput: Codable, Sendable {
    let value: String
}

private struct MockToolOutput: Codable, CustomStringConvertible, Sendable {
    let result: String
    
    var description: String {
        return result
    }
}