import Testing
@testable import SwiftAgent
@testable import AgentTools
import OpenFoundationModels

@Suite("Agents Tests")
struct AgentsTests {
    
    // Test Agent を定義（テスト用）
    struct TestAgent: Agent {
        let instructions: String
        let tools: [any OpenFoundationModels.Tool]
        
        init(instructions: String = "You are a helpful assistant", tools: [any OpenFoundationModels.Tool] = []) {
            self.instructions = instructions
            self.tools = tools
        }
        
        @StepBuilder
        var body: some Step {
            ModelStep<String, String>(
                tools: tools,
                instructions: instructions
            ) { input in
                input
            }
        }
    }
    
    @Test("Basic Agent Creation")
    func basicAgentCreation() async throws {
        // Test basic agent creation
        let agent = TestAgent()
        #expect(agent.instructions == "You are a helpful assistant")
        #expect(agent.tools.isEmpty)
    }
    
    @Test("Agent with Instructions")
    func agentWithInstructions() async throws {
        let instructions = "You are a helpful assistant"
        let agent = TestAgent(instructions: instructions)
        #expect(agent.instructions == instructions)
    }
    
    @Test("Agent with Tools")
    func agentWithTools() async throws {
        let fileSystemTool = FileSystemTool(workingDirectory: "/tmp")
        let agent = TestAgent(tools: [fileSystemTool])
        #expect(agent.tools.count == 1)
    }
    
    @Test("Agent Protocol Conformance")
    func agentProtocolConformance() async throws {
        let agent = TestAgent()
        
        // デフォルト値のテスト
        #expect(agent.maxTurns == 10)
        #expect(agent.guardrails.isEmpty)
        #expect(agent.tracer == nil)
    }
}