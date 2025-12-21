import Testing
@testable import SwiftAgent
@testable import AgentTools
import OpenFoundationModels
import Foundation

@Suite("Agents Tests")
struct AgentsTests {

    // Mock LanguageModel for testing
    struct MockLanguageModel: LanguageModel, Sendable {
        public var id: String { "mock-model" }

        public var isAvailable: Bool { true }

        public func supports(locale: Locale) -> Bool {
            true
        }

        public func generate(
            transcript: Transcript,
            options: GenerationOptions?
        ) async throws -> Transcript.Entry {
            return .response(Transcript.Response(
                assetIDs: [],
                segments: [
                    .text(Transcript.TextSegment(content: "Mock response"))
                ]
            ))
        }

        public func stream(
            transcript: Transcript,
            options: GenerationOptions?
        ) -> AsyncThrowingStream<Transcript.Entry, Error> {
            AsyncThrowingStream { continuation in
                continuation.yield(.response(Transcript.Response(
                    assetIDs: [],
                    segments: [
                        .text(Transcript.TextSegment(content: "Mock response"))
                    ]
                )))
                continuation.finish()
            }
        }
    }

    // Helper to create a mock session
    func createMockSession(instructions: String = "You are a helpful assistant", tools: [any OpenFoundationModels.Tool] = []) -> LanguageModelSession {
        LanguageModelSession(
            model: MockLanguageModel(),
            tools: tools
        ) {
            Instructions(instructions)
        }
    }

    @Test("LanguageModelSession Creation")
    func languageModelSessionCreation() async throws {
        let session = createMockSession()
        #expect(session.isResponding == false)
    }

    @Test("LanguageModelSession with Instructions")
    func languageModelSessionWithInstructions() async throws {
        let session = createMockSession(instructions: "You are a specialized assistant")
        #expect(session.isResponding == false)
    }

    @Test("LanguageModelSession with Tools")
    func languageModelSessionWithTools() async throws {
        let readTool = ReadTool(workingDirectory: "/tmp")
        let session = createMockSession(tools: [readTool])
        #expect(session.isResponding == false)
    }

    @Test("GenerateText Step Creation")
    func generateTextStepCreation() async throws {
        let session = createMockSession()

        // GenerateText can be created and is a valid Step
        let step = GenerateText<String>(session: session) { input in
            Prompt(input)
        }

        // Verify it conforms to Step protocol by checking the type
        #expect(type(of: step) == GenerateText<String>.self)
    }

    @Test("Transform Step")
    func transformStep() async throws {
        let transform = Transform<String, Int> { input in
            input.count
        }

        let result = try await transform.run("hello")
        #expect(result == 5)
    }

    @Test("Session Property Wrapper with withSession")
    func sessionPropertyWrapper() async throws {
        // Step that uses @Session property wrapper
        struct SessionAwareStep: Step {
            @Session var session: LanguageModelSession

            func run(_ input: String) async throws -> Bool {
                // Just verify session is accessible
                return !session.isResponding
            }
        }

        let session = createMockSession()
        let step = SessionAwareStep()

        // Run with session context
        let result = try await withSession(session) {
            try await step.run("test")
        }

        #expect(result == true)
    }

    @Test("Step run with session parameter")
    func stepRunWithSessionParameter() async throws {
        let transform = Transform<String, Int> { $0.count }
        let session = createMockSession()

        // Use the step extension that takes session parameter
        let result = try await transform.run("hello", session: session)
        #expect(result == 5)
    }
}
