//
//  ToolSearchE2ETests.swift
//  SwiftAgent
//

import Foundation
import Synchronization
import Testing
@testable import SwiftAgent

#if OpenFoundationModels
import OpenFoundationModels
@_spi(Internal) import OpenFoundationModelsCore

@Suite("ToolSearch End-to-End Flow")
struct ToolSearchE2ETests {

    // MARK: - Scripted Mock Model

    /// Language model that scripts a deterministic sequence of entries based on
    /// which tool calls / outputs have already appeared in the transcript.
    ///
    /// Turn 1:
    ///   ToolSearch search operation.
    /// Turn 2:
    ///   ToolSearch call operation targeting Weather.
    /// Turn 3:
    ///   → `response` with the assistant's final answer.
    final class ScriptedMockModel: LanguageModel, Sendable {
        private let storage: Mutex<[Transcript]> = Mutex([])

        var transcripts: [Transcript] {
            storage.withLock { $0 }
        }

        var isAvailable: Bool { true }
        func supports(locale: Locale) -> Bool { true }

        func generate(transcript: Transcript, options: GenerationOptions?) async throws -> Transcript.Entry {
            storage.withLock { $0.append(transcript) }

            let toolSearchOutputCount = transcript.reduce(into: 0) { count, entry in
                if case .toolOutput(let output) = entry, output.toolName == "ToolSearch" {
                    count += 1
                }
            }

            if toolSearchOutputCount == 0 {
                return .toolCalls(Transcript.ToolCalls([
                    Transcript.ToolCall(
                        id: UUID().uuidString,
                        toolName: "ToolSearch",
                        arguments: GeneratedContent(properties: [
                            "operation": "search",
                            "query": "Weather",
                        ])
                    )
                ]))
            }

            if toolSearchOutputCount == 1 {
                return .toolCalls(Transcript.ToolCalls([
                    Transcript.ToolCall(
                        id: UUID().uuidString,
                        toolName: "ToolSearch",
                        arguments: GeneratedContent(properties: [
                            "operation": "call",
                            "toolName": "Weather",
                            "arguments": GeneratedContent(properties: [
                                "city": "Tokyo",
                            ]),
                        ])
                    )
                ]))
            }

            return .response(Transcript.Response(
                id: UUID().uuidString,
                assetIDs: [],
                segments: [.text(Transcript.TextSegment(
                    id: UUID().uuidString,
                    content: "Weather in Tokyo: sunny"
                ))]
            ))
        }

        func stream(transcript: Transcript, options: GenerationOptions?) -> AsyncThrowingStream<Transcript.Entry, Error> {
            AsyncThrowingStream { continuation in
                Task {
                    do {
                        let entry = try await self.generate(transcript: transcript, options: options)
                        continuation.yield(entry)
                        continuation.finish()
                    } catch {
                        continuation.finish(throwing: error)
                    }
                }
            }
        }
    }

    final class UnknownToolCallModel: LanguageModel, Sendable {
        private let storage: Mutex<[Transcript]> = Mutex([])

        var transcripts: [Transcript] {
            storage.withLock { $0 }
        }

        var isAvailable: Bool { true }
        func supports(locale: Locale) -> Bool { true }

        func generate(transcript: Transcript, options: GenerationOptions?) async throws -> Transcript.Entry {
            storage.withLock { $0.append(transcript) }

            let toolSearchOutputCount = transcript.reduce(into: 0) { count, entry in
                if case .toolOutput(let output) = entry, output.toolName == "ToolSearch" {
                    count += 1
                }
            }

            if toolSearchOutputCount > 0 {
                return .response(Transcript.Response(
                    id: UUID().uuidString,
                    assetIDs: [],
                    segments: [.text(Transcript.TextSegment(
                        id: UUID().uuidString,
                        content: "The grouped tool call failed and can be retried."
                    ))]
                ))
            }

            return .toolCalls(Transcript.ToolCalls([
                Transcript.ToolCall(
                    id: UUID().uuidString,
                    toolName: "ToolSearch",
                    arguments: GeneratedContent(properties: [
                        "operation": "call",
                        "toolName": "MissingTool",
                        "arguments": GeneratedContent(properties: [
                            "value": "payload",
                        ]),
                    ])
                )
            ]))
        }

        func stream(transcript: Transcript, options: GenerationOptions?) -> AsyncThrowingStream<Transcript.Entry, Error> {
            AsyncThrowingStream { continuation in
                Task {
                    do {
                        continuation.yield(try await generate(transcript: transcript, options: options))
                        continuation.finish()
                    } catch {
                        continuation.finish(throwing: error)
                    }
                }
            }
        }
    }

    // MARK: - Test Tools

    struct WeatherTool: Tool {
        let name = "Weather"
        let description = "Get weather information for a city"

        @Generable
        struct Arguments {
            @Guide(description: "The city name")
            let city: String
        }

        typealias Output = String

        func call(arguments: Arguments) async throws -> String {
            "Weather in \(arguments.city): sunny"
        }
    }

    struct CalculatorTool: Tool {
        let name = "Calculator"
        let description = "Perform mathematical calculations"

        @Generable
        struct Arguments {
            @Guide(description: "The expression to evaluate")
            let expression: String
        }

        typealias Output = String

        func call(arguments: Arguments) async throws -> String {
            "Result: 42"
        }
    }

    // MARK: - Tests

    @Test("Session drives ToolSearch search → ToolSearch call → final response within one respond() call")
    func gatewayToolFlow() async throws {
        let model = ScriptedMockModel()
        let search = ToolSearchTool {
            WeatherTool()
            CalculatorTool()
        }

        let session = LanguageModelSession(
            model: model,
            tools: search.gatewayTools(),
            instructions: "You are a helpful assistant."
        )

        let response = try await session.respond(to: "What is the weather in Tokyo?")

        #expect(response.content == "Weather in Tokyo: sunny")

        // The model was invoked three times: initial, after search, after call.
        #expect(model.transcripts.count == 3)
    }

    @Test("Initial instructions surface only ToolSearch with full gateway schema")
    func initialInstructionsExposeOnlyGatewaySchema() async throws {
        let model = ScriptedMockModel()
        let search = ToolSearchTool {
            WeatherTool()
            CalculatorTool()
        }

        let session = LanguageModelSession(
            model: model,
            tools: search.gatewayTools(),
            instructions: "You are a helpful assistant."
        )

        _ = try await session.respond(to: "What is the weather in Tokyo?")

        let firstTranscript = try #require(model.transcripts.first)
        let instructions = try #require(firstTranscript.compactMap { entry -> Transcript.Instructions? in
            if case .instructions(let i) = entry { return i } else { return nil }
        }.first)

        let toolSearchDef = try #require(instructions.toolDefinitions.first { $0.name == "ToolSearch" })
        #expect(instructions.toolDefinitions.first { $0.name == "Weather" } == nil)
        #expect(instructions.toolDefinitions.first { $0.name == "Calculator" } == nil)

        // ToolSearch keeps its full gateway schema without exposing grouped tools directly.
        let toolSearchSchema = toolSearchDef.parameters.toSchemaDictionary()
        let gatewayBranches = toolSearchSchema["anyOf"] as? [[String: Any]] ?? []
        #expect(!gatewayBranches.isEmpty, "ToolSearch itself must expose its gateway branch schema")
        #expect(String(describing: toolSearchSchema).contains("operation"))
        #expect(String(describing: toolSearchSchema).contains("toolName"))
        #expect(String(describing: toolSearchSchema).contains("arguments"))
    }

    @Test("ToolSearch output reveals the Weather JSONSchema inside a <function> block")
    func toolSearchOutputRevealsSchema() async throws {
        let model = ScriptedMockModel()
        let search = ToolSearchTool {
            WeatherTool()
            CalculatorTool()
        }

        let session = LanguageModelSession(
            model: model,
            tools: search.gatewayTools(),
            instructions: "You are a helpful assistant."
        )

        _ = try await session.respond(to: "What is the weather in Tokyo?")

        // The transcript passed to the model on the second turn must contain
        // the ToolSearch output with the revealed Weather schema.
        let secondTranscript = try #require(model.transcripts.dropFirst().first)
        let searchOutput = try #require(secondTranscript.compactMap { entry -> Transcript.ToolOutput? in
            if case .toolOutput(let out) = entry, out.toolName == "ToolSearch" { return out } else { return nil }
        }.first)

        let searchText = searchOutput.segments.compactMap { segment -> String? in
            if case .text(let t) = segment { return t.content } else { return nil }
        }.joined(separator: "\n")

        #expect(searchText.contains("<function>"))
        #expect(searchText.contains("\"name\":\"Weather\""))
        #expect(searchText.contains("\"city\""))
    }

    @Test("Session surfaces ToolSearch call failures as retryable tool output")
    func toolSearchUnknownGroupedToolReturnsRetryableOutput() async throws {
        let model = UnknownToolCallModel()
        let search = ToolSearchTool {
            WeatherTool()
        }

        let session = LanguageModelSession(
            model: model,
            tools: search.gatewayTools(),
            instructions: "You are a helpful assistant."
        )

        let response = try await session.respond(to: "Use the missing grouped tool.")

        #expect(response.content == "The grouped tool call failed and can be retried.")
        #expect(model.transcripts.count == 2)

        let secondTranscript = try #require(model.transcripts.dropFirst().first)
        let output = try #require(secondTranscript.compactMap { entry -> Transcript.ToolOutput? in
            if case .toolOutput(let output) = entry, output.toolName == "ToolSearch" {
                return output
            }
            return nil
        }.first)
        let outputText = output.segments.compactMap { segment -> String? in
            if case .text(let text) = segment {
                return text.content
            }
            return nil
        }.joined(separator: "\n")

        #expect(outputText.contains("ToolSearch could not execute"))
        #expect(outputText.contains("Requested toolName: MissingTool"))
        #expect(outputText.contains("Available grouped tool names: Weather"))
    }
}
#endif
