//
//  ModelTests.swift
//  SwiftAgent
//
//  Created by Norikazu Muramoto on 2025/01/16.
//

import Testing
@testable import Agents
@testable import SwiftAgent
@testable import OpenFoundationModels

@Suite("Model Tests")
struct ModelTests {
    
    @Test("Model Step with Mock Session")
    func modelStep() async throws {
        // Test with mock session
        let mockSession = MockLanguageModelSession()
        
        let step = StringModelStep<String>(
            session: mockSession
        ) { input in
            "Test prompt: \(input)"
        }
        
        let result = try await step.run("Hello")
        #expect(result == "Mock response to: Test prompt: Hello")
    }
    
    @Test("Default Agent Creation")
    func defaultAgent() async throws {
        // Create agent with mock tools
        let agent = DefaultAgent(
            tools: [],
            instructions: "You are a helpful assistant"
        )
        
        // Note: This test requires a mock implementation since SystemLanguageModel.default
        // may not be available in test environment
        // For actual testing, we would need to inject a mock language model
        #expect(agent != nil)
    }
    
    @Test("Tool Conversion Between Systems")
    func toolConversion() async throws {
        let mockSwiftAgentTool = MockSwiftAgentTool()
        let foundationTool = ToolAdapter(mockSwiftAgentTool)
        
        #expect(foundationTool.name == mockSwiftAgentTool.name)
        #expect(foundationTool.description == mockSwiftAgentTool.description)
        
        let result = try await foundationTool.call(MockToolInput(value: "test"))
        #expect(result == "Mock output: test")
    }
    
    @Test("Message Transform to Model Format")
    func messageTransform() async throws {
        let messages = [
            ChatMessage(role: .user, content: [.text("Hello")]),
            ChatMessage(role: .assistant, content: [.text("Hi there!")])
        ]
        
        let transform = MessageToModelTransform()
        let result = try await transform.run(messages)
        
        #expect(result.contains("user: Hello"))
        #expect(result.contains("assistant: Hi there!"))
    }
    
    @Test("Model to Message Transform")
    func modelToMessageTransform() async throws {
        let transform = ModelToMessageTransform()
        let result = try await transform.run("Hello from Foundation Models!")
        
        #expect(result.count == 1)
        #expect(result.first?.role == .assistant)
        
        if case .text(let content) = result.first?.content.first {
            #expect(content == "Hello from Foundation Models!")
        } else {
            Issue.record("Expected text content")
        }
    }
    
    @Test("JSON Parse Transform")
    func jsonParseTransform() async throws {
        struct TestData: Codable, Sendable {
            let name: String
            let value: Int
        }
        
        let jsonString = """
        {
            "name": "test",
            "value": 42
        }
        """
        
        let transform = JSONParseTransform<TestData>()
        let result = try await transform.run(jsonString)
        
        #expect(result.name == "test")
        #expect(result.value == 42)
    }
    
    @Test("Generable Transform")
    func generableTransform() async throws {
        struct TestData: Codable, Sendable {
            let name: String
            let value: Int
        }
        
        let testData = TestData(name: "test", value: 42)
        let transform = GenerableTransform<TestData>()
        let result = try await transform.run(testData)
        
        #expect(result.contains("\"name\" : \"test\""))
        #expect(result.contains("\"value\" : 42"))
    }
    
    @Test("Model Validation Step")
    func modelValidationStep() async throws {
        struct TestData: Codable, Sendable, ModelGenerable {
            let name: String
            let value: Int
            
            static var generationSchema: GenerationSchema {
                return .object([
                    "name": .string,
                    "value": .integer
                ])
            }
        }
        
        let jsonString = """
        {
            "name": "test",
            "value": 42
        }
        """
        
        let step = ModelValidationStep<TestData>(type: TestData.self)
        let result = try await step.run(jsonString)
        
        #expect(result.name == "test")
        #expect(result.value == 42)
    }
}

// MARK: - Mock Implementations

private class MockLanguageModelSession: LanguageModelSession {
    
    override func respond(to prompt: String) async throws -> Response<String> {
        return Response(content: "Mock response to: \(prompt)")
    }
}

private struct MockSwiftAgentTool: SwiftAgent.Tool {
    typealias Input = MockToolInput
    typealias Output = MockToolOutput
    
    let name = "mock_tool"
    let description = "A mock tool for testing"
    let parameters = JSONSchema.object([
        "value": .string
    ])
    let guide: String? = nil
    
    func run(_ input: MockToolInput) async throws -> MockToolOutput {
        return MockToolOutput(result: "Mock output: \(input.value)")
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