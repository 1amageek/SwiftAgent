import Testing
@testable import SwiftAgent
@testable import AgentTools
import OpenFoundationModels

@Suite("Agents Tests")
struct AgentsTests {
    
    // Test Agent を定義（テスト用）
    struct TestAgent: Agent {
        @Session
        var session: LanguageModelSession
        
        init(instructions: String = "You are a helpful assistant", tools: [any OpenFoundationModels.Tool] = []) {
            self._session = Session(wrappedValue: LanguageModelSession(
                model: SystemLanguageModel.default,
                tools: tools,
                instructions: Instructions(instructions)
            ))
        }
        
        @StepBuilder
        var body: some Step {
            GenerateText<String>(session: $session) { input in
                Prompt(input)
            }
        }
    }
    
    @Test("Basic Agent Creation")
    func basicAgentCreation() async throws {
        // Test basic agent creation
        let agent = TestAgent()
        // セッションが正しく作成されていることを確認
        #expect(agent.session.instructions != nil)
        #expect(agent.session.tools.isEmpty)
    }
    
    @Test("Agent with Instructions")
    func agentWithInstructions() async throws {
        let instructions = "You are a specialized assistant"
        let agent = TestAgent(instructions: instructions)
        // Instructions が設定されていることを確認（内容は直接アクセスできない）
        #expect(agent.session.instructions != nil)
    }
    
    @Test("Agent with Tools")
    func agentWithTools() async throws {
        let readTool = ReadTool(workingDirectory: "/tmp")
        let agent = TestAgent(tools: [readTool])
        #expect(agent.session.tools.count == 1)
    }
    
    @Test("Agent Protocol Conformance")
    func agentProtocolConformance() async throws {
        let agent = TestAgent()
        
        // デフォルト値のテスト
        #expect(agent.maxTurns == 10)
        #expect(agent.guardrails.isEmpty)
    }
}