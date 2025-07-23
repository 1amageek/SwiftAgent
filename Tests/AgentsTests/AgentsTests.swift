import Testing
@testable import SwiftAgent
@testable import Agents

@Suite("Agents Tests")
struct AgentsTests {
    
    @Test("Basic Agent Creation")
    func basicAgentCreation() async throws {
        // Test basic agent creation
        let agent = DefaultAgent()
        #expect(agent != nil)
    }
    
    @Test("Agent with Instructions")
    func agentWithInstructions() async throws {
        let instructions = "You are a helpful assistant"
        let agent = DefaultAgent(instructions: instructions)
        #expect(agent != nil)
    }
    
    @Test("Agent with Tools")
    func agentWithTools() async throws {
        let agent = DefaultAgent(tools: [])
        #expect(agent != nil)
    }
}