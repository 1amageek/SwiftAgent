//
//  ToolSearchToolTests.swift
//  SwiftAgent
//

import Foundation
import Synchronization
import Testing
@testable import SwiftAgent

#if OpenFoundationModels
import OpenFoundationModels
@_spi(Internal) import OpenFoundationModelsCore
#endif

@Suite("ToolSearchTool Tests")
struct ToolSearchToolTests {

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

    struct GitHubSearchTool: Tool {
        let name = "mcp__github__search_repos"
        let description = "Search for GitHub repositories by query string"

        @Generable
        struct Arguments {
            @Guide(description: "The search query")
            let query: String
        }

        typealias Output = String

        func call(arguments: Arguments) async throws -> String {
            "Found repos"
        }
    }

    final class ToolCallRecorder: Sendable {
        private let storage = Mutex<[String]>([])

        var names: [String] {
            storage.withLock { $0 }
        }

        func append(_ name: String) {
            storage.withLock { $0.append(name) }
        }
    }

    struct RecordingMiddleware: ToolMiddleware {
        let recorder: ToolCallRecorder

        func handle(_ context: ToolContext, next: @escaping Next) async throws -> ToolResult {
            recorder.append(context.toolName)
            return try await next(context)
        }
    }

    // MARK: - Construction

    @Test("ToolSearchTool collects inner tools via builder")
    func builderCollectsInnerTools() throws {
        let search = ToolSearchTool {
            WeatherTool()
            CalculatorTool()
        }

        #expect(search.innerTools.count == 2)
        #expect(search.innerTools.map(\.name) == ["Weather", "Calculator"])
    }

    @Test("ToolSearchTool description lists inner tool names with summaries")
    func descriptionListsInnerToolNames() throws {
        let search = ToolSearchTool {
            WeatherTool()
            CalculatorTool()
        }

        #expect(search.description.contains("Weather — Get weather information for a city"))
        #expect(search.description.contains("Calculator — Perform mathematical calculations"))
        #expect(search.description.contains("Use operation \"call\""))
    }

    // MARK: - Search

    @Test("select: query returns matched tools by exact name")
    func selectQueryReturnsExactMatches() async throws {
        let search = ToolSearchTool {
            WeatherTool()
            CalculatorTool()
            GitHubSearchTool()
        }

        let output = try await search.call(arguments: .init(query: "select:Weather,Calculator"))

        #expect(output.contains("\"name\":\"Weather\""))
        #expect(output.contains("\"name\":\"Calculator\""))
        #expect(!output.contains("\"name\":\"mcp__github__search_repos\""))
    }

    @Test("select: with unknown name produces no match for that name")
    func selectQuerySkipsUnknownNames() async throws {
        let search = ToolSearchTool {
            WeatherTool()
        }

        let output = try await search.call(arguments: .init(query: "select:DoesNotExist"))
        #expect(output.contains("No matching tools"))
    }

    @Test("keyword query matches by name and description, ranks name matches higher")
    func keywordQueryRanksResults() async throws {
        let search = ToolSearchTool {
            WeatherTool()
            CalculatorTool()
            GitHubSearchTool()
        }

        let output = try await search.call(arguments: .init(query: "search", maxResults: 1))
        // "search" appears in GitHub tool's name — should rank highest
        #expect(output.contains("\"name\":\"mcp__github__search_repos\""))
    }

    @Test("Keyword query returns top-N by maxResults")
    func keywordQueryRespectsMaxResults() async throws {
        let search = ToolSearchTool {
            WeatherTool()
            CalculatorTool()
            GitHubSearchTool()
        }

        let output = try await search.call(arguments: .init(query: "tool", maxResults: 2))
        let matchCount = output.components(separatedBy: "<function>").count - 1
        #expect(matchCount <= 2)
    }

    @Test("Empty query returns up to maxResults tools as fallback")
    func emptyQueryReturnsDefaults() async throws {
        let search = ToolSearchTool {
            WeatherTool()
            CalculatorTool()
        }

        let output = try await search.call(arguments: .init(query: "   ", maxResults: 2))
        #expect(output.contains("<function>"))
    }

    @Test("No-match query reports no matching tools")
    func noMatchReportsClearly() async throws {
        let search = ToolSearchTool {
            WeatherTool()
        }

        let output = try await search.call(arguments: .init(query: "xyzzy_nothing_matches"))
        #expect(output.contains("No matching tools"))
    }

    // MARK: - Schema rendering

    @Test("Rendered function block includes parsable JSON with name, description and parameters")
    func renderedFunctionBlockIsParsable() async throws {
        let search = ToolSearchTool {
            WeatherTool()
        }

        let output = try await search.call(arguments: .init(query: "select:Weather"))

        let prefix = "<function>"
        let suffix = "</function>"
        let start = try #require(output.range(of: prefix))
        let end = try #require(output.range(of: suffix, range: start.upperBound..<output.endIndex))
        let jsonString = String(output[start.upperBound..<end.lowerBound])

        let data = try #require(jsonString.data(using: .utf8))
        let parsed = try JSONSerialization.jsonObject(with: data) as? [String: Any]

        let json = try #require(parsed)
        #expect(json["name"] as? String == "Weather")
        #expect(json["description"] as? String == "Get weather information for a city")
        #expect(json["parameters"] is [String: Any])
    }

    @Test("Returned parameters is a full JSON Schema (type/properties/required)")
    func returnedParametersIsFullJSONSchema() async throws {
        let search = ToolSearchTool {
            WeatherTool()
        }

        let output = try await search.call(arguments: .init(query: "select:Weather"))

        let prefix = "<function>"
        let suffix = "</function>"
        let start = try #require(output.range(of: prefix))
        let end = try #require(output.range(of: suffix, range: start.upperBound..<output.endIndex))
        let jsonString = String(output[start.upperBound..<end.lowerBound])

        let data = try #require(jsonString.data(using: .utf8))
        let parsed = try #require(try JSONSerialization.jsonObject(with: data) as? [String: Any])

        let parameters = try #require(parsed["parameters"] as? [String: Any])

        // Full JSON Schema: has object type, declares `city` property, marks it required
        #expect(parameters["type"] as? String == "object")

        let properties = try #require(parameters["properties"] as? [String: Any])
        #expect(properties["city"] != nil, "properties must include the Weather tool's `city` argument")

        let cityProperty = try #require(properties["city"] as? [String: Any])
        #expect(cityProperty["type"] as? String == "string")

        let required = try #require(parameters["required"] as? [String])
        #expect(required.contains("city"))
    }

    @Test("Call operation dispatches the selected inner tool")
    func callOperationDispatchesInnerTool() async throws {
        let search = ToolSearchTool {
            WeatherTool()
        }

        let output = try await search.call(arguments: .init(
            operation: "call",
            toolName: "Weather",
            argumentsJSON: #"{"city":"Tokyo"}"#
        ))

        #expect(output == "Weather in Tokyo: sunny")
    }

    @Test("Runtime registers ToolSearch inner tools as hidden and applies middleware")
    func runtimeRegistersInnerToolsAsHidden() async throws {
        let recorder = ToolCallRecorder()
        let search = ToolSearchTool {
            WeatherTool()
        }

        var configuration = ToolRuntimeConfiguration.empty
        configuration.use(RecordingMiddleware(recorder: recorder))
        configuration.register(search)
        let runtime = ToolRuntime(configuration: configuration)

        let output = try await runtime.execute(
            toolName: "ToolSearch",
            argumentsJSON: GeneratedContent(properties: [
                "operation": "call",
                "toolName": "Weather",
                "argumentsJSON": #"{"city":"Tokyo"}"#,
            ]).jsonString
        )

        #expect(output == "Weather in Tokyo: sunny")
        #expect(recorder.names == ["ToolSearch", "Weather"])
        #expect(runtime.publicTools().map(\.name) == ["ToolSearch"])
    }

    // MARK: - Container integration with LanguageModelSession (OFM trait only)

    #if OpenFoundationModels

    final class MockLanguageModel: LanguageModel, @unchecked Sendable {
        var capturedTranscript: Transcript?

        var isAvailable: Bool { true }

        func supports(locale: Locale) -> Bool { true }

        func generate(transcript: Transcript, options: GenerationOptions?) async throws -> Transcript.Entry {
            capturedTranscript = transcript
            return .response(Transcript.Response(
                id: UUID().uuidString,
                assetIDs: [],
                segments: [.text(Transcript.TextSegment(id: UUID().uuidString, content: "ok"))]
            ))
        }

        func stream(transcript: Transcript, options: GenerationOptions?) -> AsyncThrowingStream<Transcript.Entry, Error> {
            capturedTranscript = transcript
            return AsyncThrowingStream { continuation in
                continuation.yield(.response(Transcript.Response(
                    id: UUID().uuidString,
                    assetIDs: [],
                    segments: [.text(Transcript.TextSegment(id: UUID().uuidString, content: "ok"))]
                )))
                continuation.finish()
            }
        }
    }

    @Test("gatewayTools() registers only ToolSearch with the session")
    func sessionRegistersOnlyGatewayTool() async throws {
        let model = MockLanguageModel()
        let search = ToolSearchTool {
            WeatherTool()
            CalculatorTool()
        }

        let session = LanguageModelSession(
            model: model,
            tools: search.gatewayTools(),
            instructions: "You are a helpful assistant."
        )

        _ = try await session.respond(to: "Hi")

        let captured = try #require(model.capturedTranscript)
        let instructions = try #require(captured.compactMap { entry -> Transcript.Instructions? in
            if case .instructions(let i) = entry { return i } else { return nil }
        }.first)

        let names: [String] = instructions.toolDefinitions.map { $0.name }
        #expect(names.contains("ToolSearch"))
        #expect(!names.contains("Weather"))
        #expect(!names.contains("Calculator"))
    }

    @Test("Gateway tool keeps schema while sibling non-gateway tools keep their schemas")
    func gatewayAndSiblingToolSchemas() async throws {
        let model = MockLanguageModel()
        let search = ToolSearchTool {
            WeatherTool()
        }

        let session = LanguageModelSession(
            model: model,
            tools: search.gatewayTools() + [CalculatorTool()],
            instructions: "You are a helpful assistant."
        )

        _ = try await session.respond(to: "Hi")

        let captured = try #require(model.capturedTranscript)
        let instructions = try #require(captured.compactMap { entry -> Transcript.Instructions? in
            if case .instructions(let i) = entry { return i } else { return nil }
        }.first)

        #expect(instructions.toolDefinitions.first { $0.name == "Weather" } == nil)

        // Sibling non-container tool keeps its full schema
        let calc = try #require(instructions.toolDefinitions.first { $0.name == "Calculator" })
        let calcParamsDict = calc.parameters.toSchemaDictionary()
        let calcProps = calcParamsDict["properties"] as? [String: Any] ?? [:]
        #expect(!calcProps.isEmpty, "non-container tool should keep its real parameters schema")

        // Container tool itself keeps its full schema
        let toolSearch = try #require(instructions.toolDefinitions.first { $0.name == "ToolSearch" })
        let searchParamsDict = toolSearch.parameters.toSchemaDictionary()
        let searchProps = searchParamsDict["properties"] as? [String: Any] ?? [:]
        #expect(!searchProps.isEmpty, "ToolSearchTool itself should keep its real parameters schema")
    }

    #endif
}
