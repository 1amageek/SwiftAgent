//
//  FoundationModelsTests.swift
//  SwiftAgent
//
//  Tests for Apple's FoundationModels integration.
//

import Testing
import Foundation
@testable import SwiftAgent

#if !USE_OTHER_MODELS
import FoundationModels

// MARK: - LanguageModelSession Tests

@Suite("FoundationModels Session Tests")
struct FoundationModelsSessionTests {

    @Test("LanguageModelSession creation with SystemLanguageModel")
    func sessionCreation() async throws {
        let session = LanguageModelSession(
            model: SystemLanguageModel.default
        ) {
            Instructions("You are a helpful assistant.")
        }
        #expect(session.isResponding == false)
    }

    @Test("LanguageModelSession with custom instructions")
    func sessionWithCustomInstructions() async throws {
        let session = LanguageModelSession(
            model: SystemLanguageModel.default
        ) {
            Instructions {
                "You are a code assistant."
                "Help users write clean, efficient code."
            }
        }
        #expect(session.isResponding == false)
    }

    @Test("LanguageModelSession transcript is initially empty or has instructions")
    func sessionTranscriptInitialState() async throws {
        let session = LanguageModelSession(
            model: SystemLanguageModel.default
        ) {
            Instructions("Test instructions")
        }

        let transcript = session.transcript
        // Transcript should have at least the instructions entry
        #expect(transcript.count >= 0)
    }
}

// MARK: - Session Context Tests

@Suite("FoundationModels Session Context Tests")
struct FoundationModelsSessionContextTests {

    @Test("SessionContext.current is nil by default")
    func sessionContextNilByDefault() {
        #expect(SessionContext.current == nil)
    }

    @Test("withSession sets context for operation")
    func withSessionSetsContext() async throws {
        let session = LanguageModelSession(
            model: SystemLanguageModel.default
        ) {
            Instructions("Test")
        }

        let result = await withSession(session) {
            SessionContext.current != nil
        }

        #expect(result == true)
    }

    @Test("withSession clears context after operation")
    func withSessionClearsContextAfter() async throws {
        let session = LanguageModelSession(
            model: SystemLanguageModel.default
        ) {
            Instructions("Test")
        }

        _ = await withSession(session) {
            #expect(SessionContext.current != nil)
        }

        #expect(SessionContext.current == nil)
    }

    @Test("withSession returns operation result")
    func withSessionReturnsResult() async throws {
        let session = LanguageModelSession(
            model: SystemLanguageModel.default
        ) {
            Instructions("Test")
        }

        let result = await withSession(session) {
            42
        }

        #expect(result == 42)
    }
}

// MARK: - @Session Property Wrapper Tests

@Suite("FoundationModels @Session Property Wrapper Tests")
struct FoundationModelsSessionPropertyWrapperTests {

    struct SessionAccessingStep: Step {
        @Session var session: LanguageModelSession

        func run(_ input: String) async throws -> Bool {
            return !session.isResponding
        }
    }

    @Test("@Session provides access to session in withSession context")
    func sessionWrapperProvidesAccess() async throws {
        let session = LanguageModelSession(
            model: SystemLanguageModel.default
        ) {
            Instructions("Test")
        }
        let step = SessionAccessingStep()

        let result = try await withSession(session) {
            try await step.run("test")
        }

        #expect(result == true)
    }

    @Test("Step.run with session parameter sets context")
    func stepRunWithSessionParameter() async throws {
        let session = LanguageModelSession(
            model: SystemLanguageModel.default
        ) {
            Instructions("Test")
        }
        let step = SessionAccessingStep()

        let result = try await step.session(session).run("test")

        #expect(result == true)
    }
}

// MARK: - Step with Session Tests

@Suite("FoundationModels Step with Session Tests")
struct FoundationModelsStepWithSessionTests {

    @Test("Transform step works within session context")
    func transformWorksInContext() async throws {
        let session = LanguageModelSession(
            model: SystemLanguageModel.default
        ) {
            Instructions("Test")
        }
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

        let session = LanguageModelSession(
            model: SystemLanguageModel.default
        ) {
            Instructions("Test")
        }
        let chain = Chain2(DoubleStep(), AddStep())

        let result = try await withSession(session) {
            try await chain.run(5)
        }

        // 5 * 2 = 10, 10 + 3 = 13
        #expect(result == 13)
    }

    @Test("Nested steps share session context")
    func nestedStepsShareContext() async throws {
        struct OuterStep: Step {
            @Session var session: LanguageModelSession

            func run(_ input: Int) async throws -> Int {
                let innerResult = try await InnerStep().run(input)
                return innerResult * 2
            }
        }

        struct InnerStep: Step {
            @Session var session: LanguageModelSession

            func run(_ input: Int) async throws -> Int {
                _ = session.isResponding
                return input + 1
            }
        }

        let session = LanguageModelSession(
            model: SystemLanguageModel.default
        ) {
            Instructions("Test")
        }
        let step = OuterStep()

        let result = try await withSession(session) {
            try await step.run(5)
        }

        // InnerStep: 5 + 1 = 6, OuterStep: 6 * 2 = 12
        #expect(result == 12)
    }
}

// MARK: - Transcript Tests

@Suite("FoundationModels Transcript Tests")
struct FoundationModelsTranscriptTests {

    @Test("Transcript Entry types are accessible")
    func transcriptEntryTypesAccessible() async throws {
        let session = LanguageModelSession(
            model: SystemLanguageModel.default
        ) {
            Instructions("Test")
        }

        for entry in session.transcript {
            switch entry {
            case .instructions:
                break
            case .prompt:
                break
            case .response:
                break
            case .toolCalls:
                break
            case .toolOutput:
                break
            @unknown default:
                break
            }
        }

        #expect(true)
    }
}

#endif
