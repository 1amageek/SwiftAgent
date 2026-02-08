import Testing
import Foundation
@testable import SwiftAgent

#if OpenFoundationModels
import OpenFoundationModels

// MARK: - Test Helpers

/// Mock LanguageModel for testing
struct MockLanguageModel: LanguageModel, Sendable {
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
func createTestSession() -> LanguageModelSession {
    LanguageModelSession(model: MockLanguageModel()) {
        Instructions("Test instructions")
    }
}

// MARK: - Session Context Tests

@Suite("Session Context Tests")
struct SessionContextTests {

    @Test("SessionContext.current is nil by default")
    func sessionContextNilByDefault() {
        // Outside of withSession, current should be nil
        #expect(SessionContext.current == nil)
    }

    @Test("withSession sets context for operation")
    func withSessionSetsContext() async throws {
        let session = createTestSession()

        let result = await withSession(session) {
            SessionContext.current != nil
        }

        #expect(result == true)
    }

    @Test("withSession clears context after operation")
    func withSessionClearsContextAfter() async throws {
        let session = createTestSession()

        _ = await withSession(session) {
            // Context is set here
            #expect(SessionContext.current != nil)
        }

        // Context should be nil after withSession completes
        #expect(SessionContext.current == nil)
    }

    @Test("withSession returns operation result")
    func withSessionReturnsResult() async throws {
        let session = createTestSession()

        let result = await withSession(session) {
            42
        }

        #expect(result == 42)
    }

    @Test("withSession propagates errors")
    func withSessionPropagatesErrors() async throws {
        struct TestError: Error {}
        let session = createTestSession()

        await #expect(throws: TestError.self) {
            try await withSession(session) {
                throw TestError()
            }
        }
    }
}

// MARK: - @Session Property Wrapper Tests

@Suite("Session Property Wrapper Tests")
struct SessionPropertyWrapperTests {

    /// Step that uses @Session to access the session
    struct SessionAccessingStep: Step {
        @Session var session: LanguageModelSession

        func run(_ input: String) async throws -> Bool {
            // Verify session is accessible and has expected property
            return !session.isResponding
        }
    }

    @Test("@Session provides access to session in withSession context")
    func sessionWrapperProvidesAccess() async throws {
        let session = createTestSession()
        let step = SessionAccessingStep()

        let result = try await withSession(session) {
            try await step.run("test")
        }

        #expect(result == true)
    }

    @Test(".session() modifier provides session context")
    func sessionModifierProvidesContext() async throws {
        let session = createTestSession()
        let step = SessionAccessingStep()

        let result = try await step
            .session(session)
            .run("test")

        #expect(result == true)
    }

    @Test(".session() modifier works with chained steps")
    func sessionModifierWorksWithChain() async throws {
        struct DoubleStep: Step, Sendable {
            func run(_ input: Int) async throws -> Int { input * 2 }
        }

        struct SessionAwareStep: Step {
            @Session var session: LanguageModelSession
            func run(_ input: Int) async throws -> Int {
                _ = session.isResponding
                return input + 5
            }
        }

        let session = createTestSession()
        let chain = Chain2(DoubleStep(), SessionAwareStep())

        let result = try await chain
            .session(session)
            .run(10)

        // 10 * 2 = 20, 20 + 5 = 25
        #expect(result == 25)
    }
}

// MARK: - Nested Session Tests

@Suite("Nested Session Tests")
struct NestedSessionTests {

    /// Outer step that calls inner step
    struct OuterStep: Step {
        @Session var session: LanguageModelSession

        func run(_ input: Int) async throws -> Int {
            let innerResult = try await InnerStep().run(input)
            return innerResult * 2
        }
    }

    /// Inner step that also uses @Session
    struct InnerStep: Step {
        @Session var session: LanguageModelSession

        func run(_ input: Int) async throws -> Int {
            // Verify session is accessible
            _ = session.isResponding
            return input + 1
        }
    }

    @Test("Nested steps share the same session context")
    func nestedStepsShareContext() async throws {
        let session = createTestSession()
        let step = OuterStep()

        let result = try await withSession(session) {
            try await step.run(5)
        }

        // InnerStep: 5 + 1 = 6, OuterStep: 6 * 2 = 12
        #expect(result == 12)
    }

    @Test("Deeply nested steps access session")
    func deeplyNestedStepsAccessSession() async throws {
        struct Level1: Step {
            @Session var session: LanguageModelSession
            func run(_ input: Int) async throws -> Int {
                try await Level2().run(input) + 1
            }
        }

        struct Level2: Step {
            @Session var session: LanguageModelSession
            func run(_ input: Int) async throws -> Int {
                try await Level3().run(input) + 1
            }
        }

        struct Level3: Step {
            @Session var session: LanguageModelSession
            func run(_ input: Int) async throws -> Int {
                _ = session.isResponding // Verify access
                return input + 1
            }
        }

        let session = createTestSession()
        let result = try await withSession(session) {
            try await Level1().run(0)
        }

        // Level3: 0 + 1 = 1, Level2: 1 + 1 = 2, Level1: 2 + 1 = 3
        #expect(result == 3)
    }
}

// MARK: - Session with Regular Steps Tests

@Suite("Session with Regular Steps Tests")
struct SessionWithRegularStepsTests {

    @Test("Regular step works within session context")
    func regularStepWorksInContext() async throws {
        let session = createTestSession()
        let transform = Transform<Int, Int> { $0 * 2 }

        let result = try await withSession(session) {
            try await transform.run(5)
        }

        #expect(result == 10)
    }

    @Test("Chain of steps works within session context")
    func chainWorksInContext() async throws {
        struct DoubleStep: Step, Sendable {
            func run(_ input: Int) async throws -> Int { input * 2 }
        }
        struct AddStep: Step, Sendable {
            func run(_ input: Int) async throws -> Int { input + 3 }
        }

        let session = createTestSession()
        let chain = Chain2(DoubleStep(), AddStep())

        let result = try await withSession(session) {
            try await chain.run(5)
        }

        // 5 * 2 = 10, 10 + 3 = 13
        #expect(result == 13)
    }

    @Test("Mixed session-aware and regular steps")
    func mixedStepsWork() async throws {
        struct SessionAwareStep: Step {
            @Session var session: LanguageModelSession
            func run(_ input: Int) async throws -> Int {
                _ = session.isResponding
                return input + 10
            }
        }

        let session = createTestSession()
        let transform = Transform<Int, Int> { $0 * 2 }
        let sessionStep = SessionAwareStep()

        let result = try await withSession(session) {
            let t1 = try await transform.run(5)
            return try await sessionStep.run(t1)
        }

        // 5 * 2 = 10, 10 + 10 = 20
        #expect(result == 20)
    }
}

#endif
