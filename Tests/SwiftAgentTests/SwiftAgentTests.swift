import Testing
import Foundation
import SwiftAgent
@testable import AgentTools

#if USE_OTHER_MODELS
import OpenFoundationModels

// MARK: - Test Helpers

@Generable
struct AgentTestInput: Sendable {
    @Guide(description: "Test value")
    let value: String
}

/// Test output type that conforms to PromptRepresentable
struct AgentTestOutput: PromptRepresentable, Sendable {
    let message: String

    init(_ message: String) {
        self.message = message
    }

    var promptRepresentation: Prompt {
        Prompt(message)
    }
}

struct AgentTestTool: OpenFoundationModels.Tool {
    typealias Arguments = AgentTestInput
    typealias Output = AgentTestOutput

    static let name = "test"
    var name: String { Self.name }

    static let description = "Test tool for unit testing"
    var description: String { Self.description }

    func call(arguments: AgentTestInput) async throws -> AgentTestOutput {
        AgentTestOutput("Processed: \(arguments.value)")
    }
}

/// Mock LanguageModel for testing
struct AgentTestMockModel: LanguageModel, Sendable {
    var id: String { "mock-model" }
    var isAvailable: Bool { true }

    func supports(locale: Locale) -> Bool { true }

    func generate(
        transcript: Transcript,
        options: GenerationOptions?
    ) async throws -> Transcript.Entry {
        .response(Transcript.Response(
            assetIDs: [],
            segments: [.text(Transcript.TextSegment(content: "Mock response"))]
        ))
    }

    func stream(
        transcript: Transcript,
        options: GenerationOptions?
    ) -> AsyncThrowingStream<Transcript.Entry, Error> {
        AsyncThrowingStream { continuation in
            continuation.yield(.response(Transcript.Response(
                assetIDs: [],
                segments: [.text(Transcript.TextSegment(content: "Mock response"))]
            )))
            continuation.finish()
        }
    }
}

/// Helper to create a mock session
func createAgentTestSession() -> LanguageModelSession {
    LanguageModelSession(model: AgentTestMockModel()) {
        Instructions("Test instructions")
    }
}

// MARK: - Agents Tests

@Suite("Agents Tests")
struct AgentsTests {

    @Test("Tool Creation")
    func toolCreation() async throws {
        let tool = AgentTestTool()
        #expect(tool.name == "test")
        #expect(tool.description == "Test tool for unit testing")
    }

    @Test("Tool Call (Simplified)")
    func toolCallSimplified() async throws {
        let tool = AgentTestTool()
        #expect(tool.name == "test")
        #expect(tool.description.contains("Test tool"))
    }

    @Test("ReadTool Creation")
    func readToolCreation() async throws {
        let tool = ReadTool(workingDirectory: "/tmp")
        #expect(tool.name == "Read")
        #expect(!tool.description.isEmpty)
    }

    @Test("GitTool Creation")
    func gitToolCreation() async throws {
        let tool = GitTool()
        #expect(tool.name == "Git")
        #expect(!tool.description.isEmpty)
    }

    @Test("URLFetchTool Creation")
    func urlFetchToolCreation() async throws {
        let tool = URLFetchTool()
        #expect(tool.name == "WebFetch")
        #expect(!tool.description.isEmpty)
    }

    @Test("ExecuteCommandTool Creation")
    func executeCommandToolCreation() async throws {
        let tool = ExecuteCommandTool()
        #expect(tool.name == "Bash")
        #expect(!tool.description.isEmpty)
    }

    @Test("LanguageModelSession Creation")
    func languageModelSessionCreation() async throws {
        let session = createAgentTestSession()
        // Verify session is created
        #expect(session.isResponding == false)
    }

    @Test("LanguageModelSession with Instructions")
    func languageModelSessionWithInstructions() async throws {
        let session = LanguageModelSession(model: AgentTestMockModel()) {
            Instructions("You are a helpful assistant.")
        }
        // Verify session is created
        #expect(session.isResponding == false)
    }

    @Test("LanguageModelSession with Tools")
    func languageModelSessionWithTools() async throws {
        let tool = AgentTestTool()
        let session = LanguageModelSession(model: AgentTestMockModel(), tools: [tool]) {
            Instructions("Test")
        }
        // Verify session is created
        #expect(session.isResponding == false)
    }

    @Test("Transform Step")
    func transformStep() async throws {
        let transform = Transform<Int, String> { String($0) }
        let result = try await transform.run(42)
        #expect(result == "42")
    }

    @Test("GenerateText Step Creation")
    func generateTextStepCreation() async throws {
        let session = createAgentTestSession()
        let step = GenerateText(session: session) { (input: String) -> String in
            input
        }
        // Verify step is created by checking its type
        let typeName = String(describing: type(of: step))
        #expect(typeName.contains("GenerateText"))
    }

    @Test("Step run with session parameter")
    func stepRunWithSessionParameter() async throws {
        let session = createAgentTestSession()
        let transform = Transform<Int, Int> { $0 * 2 }

        let result = try await transform.run(5, session: session)
        #expect(result == 10)
    }
}

#endif
