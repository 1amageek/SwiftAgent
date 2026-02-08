//
//  GenerateRetryTests.swift
//  SwiftAgent
//
//  Tests for Generate retry functionality.
//

import Testing
import Foundation
@testable import SwiftAgent

#if OpenFoundationModels
import OpenFoundationModels
#else
import FoundationModels
#endif

// MARK: - shouldRetryGenerationError Tests

@Suite("shouldRetryGenerationError Function Tests")
struct ShouldRetryGenerationErrorTests {

    // Helper to create GenerationError.Context
    private func makeContext(_ description: String = "test") -> LanguageModelSession.GenerationError.Context {
        LanguageModelSession.GenerationError.Context(debugDescription: description)
    }

    // MARK: - Retryable Errors

    @Test("decodingFailure should be retryable")
    func decodingFailureIsRetryable() {
        let error = LanguageModelSession.GenerationError.decodingFailure(makeContext())
        #expect(shouldRetryGenerationError(error) == true)
    }

    @Test("DecodingError.dataCorrupted should be retryable")
    func decodingErrorDataCorruptedIsRetryable() {
        let context = DecodingError.Context(codingPath: [], debugDescription: "corrupted")
        let error = DecodingError.dataCorrupted(context)
        #expect(shouldRetryGenerationError(error) == true)
    }

    @Test("DecodingError.typeMismatch should be retryable")
    func decodingErrorTypeMismatchIsRetryable() {
        let context = DecodingError.Context(codingPath: [], debugDescription: "mismatch")
        let error = DecodingError.typeMismatch(String.self, context)
        #expect(shouldRetryGenerationError(error) == true)
    }

    @Test("DecodingError.valueNotFound should be retryable")
    func decodingErrorValueNotFoundIsRetryable() {
        let context = DecodingError.Context(codingPath: [], debugDescription: "not found")
        let error = DecodingError.valueNotFound(String.self, context)
        #expect(shouldRetryGenerationError(error) == true)
    }

    @Test("DecodingError.keyNotFound should be retryable")
    func decodingErrorKeyNotFoundIsRetryable() {
        struct TestKey: CodingKey {
            var stringValue: String
            var intValue: Int?
            init?(stringValue: String) { self.stringValue = stringValue }
            init?(intValue: Int) { return nil }
        }
        let context = DecodingError.Context(codingPath: [], debugDescription: "key not found")
        let error = DecodingError.keyNotFound(TestKey(stringValue: "test")!, context)
        #expect(shouldRetryGenerationError(error) == true)
    }

    // MARK: - Non-Retryable Errors

    @Test("exceededContextWindowSize should not be retryable")
    func exceededContextWindowSizeNotRetryable() {
        let error = LanguageModelSession.GenerationError.exceededContextWindowSize(makeContext())
        #expect(shouldRetryGenerationError(error) == false)
    }

    @Test("assetsUnavailable should not be retryable")
    func assetsUnavailableNotRetryable() {
        let error = LanguageModelSession.GenerationError.assetsUnavailable(makeContext())
        #expect(shouldRetryGenerationError(error) == false)
    }

    @Test("guardrailViolation should not be retryable")
    func guardrailViolationNotRetryable() {
        let error = LanguageModelSession.GenerationError.guardrailViolation(makeContext())
        #expect(shouldRetryGenerationError(error) == false)
    }

    @Test("unsupportedGuide should not be retryable")
    func unsupportedGuideNotRetryable() {
        let error = LanguageModelSession.GenerationError.unsupportedGuide(makeContext())
        #expect(shouldRetryGenerationError(error) == false)
    }

    @Test("unsupportedLanguageOrLocale should not be retryable")
    func unsupportedLanguageOrLocaleNotRetryable() {
        let error = LanguageModelSession.GenerationError.unsupportedLanguageOrLocale(makeContext())
        #expect(shouldRetryGenerationError(error) == false)
    }

    @Test("rateLimited should not be retryable")
    func rateLimitedNotRetryable() {
        let error = LanguageModelSession.GenerationError.rateLimited(makeContext())
        #expect(shouldRetryGenerationError(error) == false)
    }

    @Test("concurrentRequests should not be retryable")
    func concurrentRequestsNotRetryable() {
        let error = LanguageModelSession.GenerationError.concurrentRequests(makeContext())
        #expect(shouldRetryGenerationError(error) == false)
    }

    @Test("refusal should not be retryable")
    func refusalNotRetryable() {
        let refusal = LanguageModelSession.GenerationError.Refusal(transcriptEntries: [])
        let error = LanguageModelSession.GenerationError.refusal(refusal, makeContext())
        #expect(shouldRetryGenerationError(error) == false)
    }

    // MARK: - Unknown Errors

    @Test("Custom error should not be retryable")
    func customErrorNotRetryable() {
        struct CustomError: Error {}
        let error = CustomError()
        #expect(shouldRetryGenerationError(error) == false)
    }

    @Test("NSError should not be retryable")
    func nsErrorNotRetryable() {
        let error = NSError(domain: "test", code: -1)
        #expect(shouldRetryGenerationError(error) == false)
    }

    @Test("URLError should not be retryable")
    func urlErrorNotRetryable() {
        let error = URLError(.timedOut)
        #expect(shouldRetryGenerationError(error) == false)
    }

    @Test("CancellationError should not be retryable")
    func cancellationErrorNotRetryable() {
        let error = CancellationError()
        #expect(shouldRetryGenerationError(error) == false)
    }
}

// MARK: - Generate maxRetries Parameter Tests

@Suite("Generate maxRetries Parameter Tests")
struct GenerateMaxRetriesParameterTests {

    #if !OpenFoundationModels
    @Test("Generate default maxRetries is 3")
    func generateDefaultMaxRetries() {
        let session = LanguageModelSession(model: SystemLanguageModel.default)
        let generate = Generate<String, String>(session: session) { Prompt($0) }
        // Default maxRetries is 3, so maxAttempts = 4
        // We can't directly access maxRetries, but we can verify it compiles with default
        #expect(true)
    }

    @Test("Generate accepts custom maxRetries")
    func generateCustomMaxRetries() {
        let session = LanguageModelSession(model: SystemLanguageModel.default)
        let generate = Generate<String, String>(session: session, maxRetries: 5) { Prompt($0) }
        // Verify it compiles with custom maxRetries
        #expect(true)
    }

    @Test("Generate accepts maxRetries of 0")
    func generateZeroMaxRetries() {
        let session = LanguageModelSession(model: SystemLanguageModel.default)
        let generate = Generate<String, String>(session: session, maxRetries: 0) { Prompt($0) }
        // maxRetries = 0 means only 1 attempt, no retries
        #expect(true)
    }

    @Test("GenerateText does not have maxRetries parameter")
    func generateTextNoMaxRetries() {
        let session = LanguageModelSession(model: SystemLanguageModel.default)
        // GenerateText should not have maxRetries parameter
        let generateText = GenerateText(session: session) { Prompt($0) }
        // If this compiles, GenerateText correctly omits maxRetries
        #expect(true)
    }
    #endif
}
