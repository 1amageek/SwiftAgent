import Testing
@testable import SwiftAgent
@testable import AgentTools
import OpenFoundationModels
import Foundation

@Suite("Agents Tests")
struct AgentsTests {
    
    // Mock LanguageModel for testing
    struct MockLanguageModel: LanguageModel {
        public var isAvailable: Bool { true }
        
        public func generate(
            transcript: Transcript,
            options: GenerationOptions?
        ) async throws -> String {
            return "Mock response"
        }
        
        public func stream(
            transcript: Transcript,
            options: GenerationOptions?
        ) -> AsyncStream<String> {
            AsyncStream { continuation in
                continuation.yield("Mock")
                continuation.yield(" response")
                continuation.finish()
            }
        }
        
        public func supports(locale: Locale) -> Bool {
            true
        }
    }
    
    // Test Agent を定義（テスト用）
    struct TestAgent: Agent {
        @Session
        var session: LanguageModelSession
        
        init(instructions: String = "You are a helpful assistant", tools: [any OpenFoundationModels.Tool] = []) {
            self._session = Session(wrappedValue: LanguageModelSession(
                model: MockLanguageModel(),
                tools: tools
            ) {
                Instructions(instructions)
            })
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
        // エージェントが正しく作成されていることを確認
        #expect(agent.session.isResponding == false)
        // Transcript should contain instructions entry
        #expect(agent.session.transcript.entries.count == 1)
    }
    
    @Test("Agent with Instructions")
    func agentWithInstructions() async throws {
        let instructions = "You are a specialized assistant"
        let agent = TestAgent(instructions: instructions)
        // セッションが正しく作成されていることを確認
        #expect(agent.session.isResponding == false)
    }
    
    @Test("Agent with Tools")
    func agentWithTools() async throws {
        let readTool = ReadTool(workingDirectory: "/tmp")
        let agent = TestAgent(tools: [readTool])
        // ツールが設定されたセッションが作成されていることを確認
        #expect(agent.session.isResponding == false)
    }
    
    @Test("Agent Protocol Conformance")
    func agentProtocolConformance() async throws {
        let agent = TestAgent()
        
        // デフォルト値のテスト
        #expect(agent.maxTurns == 10)
        #expect(agent.guardrails.isEmpty)
    }
}