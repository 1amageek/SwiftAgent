//
//  FoundationModelsToolSearchE2ETests.swift
//  SwiftAgent
//
//  End-to-end progressive disclosure flow exercised against the real
//  on-device SystemLanguageModel. Opt in with
//  SWIFT_AGENT_RUN_FOUNDATION_MODELS_E2E=1 on a host where Apple
//  Intelligence is available.
//

import Testing
import Foundation
import Synchronization
@testable import SwiftAgent

#if !OpenFoundationModels
import FoundationModels

private let runFoundationModelsToolSearchE2E =
    ProcessInfo.processInfo.environment["SWIFT_AGENT_RUN_FOUNDATION_MODELS_E2E"] == "1"
    && SystemLanguageModel.default.isAvailable

@Suite("FoundationModels ToolSearch E2E", .serialized)
struct FoundationModelsToolSearchE2ETests {

    // MARK: - Instrumented Weather Tool

    final class CallLog: Sendable {
        let cities: Mutex<[String]> = Mutex([])
        var calls: [String] { cities.withLock { $0 } }
    }

    final class MiddlewareLog: Sendable {
        private let names: Mutex<[String]> = Mutex([])

        var calls: [String] {
            names.withLock { $0 }
        }

        func append(_ name: String) {
            names.withLock { $0.append(name) }
        }
    }

    struct RecordingMiddleware: ToolMiddleware {
        let log: MiddlewareLog

        func handle(_ context: ToolContext, next: @escaping Next) async throws -> ToolResult {
            log.append(context.toolName)
            return try await next(context)
        }
    }

    struct WeatherTool: Tool {
        let name = "Weather"
        let description = "Get the current weather for a given city"

        @Generable
        struct Arguments {
            @Guide(description: "The city name")
            let city: String
        }

        typealias Output = String

        let log: CallLog

        func call(arguments: Arguments) async throws -> String {
            log.cities.withLock { $0.append(arguments.city) }
            return "Weather in \(arguments.city): sunny, 22°C"
        }
    }

    // MARK: - Test

    @Test(
        "SystemLanguageModel completes ToolSearch → Weather progressive disclosure",
        .enabled(if: runFoundationModelsToolSearchE2E),
        .timeLimit(.minutes(3))
    )
    func progressiveDisclosureViaSystemModel() async throws {
        let log = CallLog()
        let search = ToolSearchTool {
            WeatherTool(log: log)
        }

        let session = LanguageModelSession(
            model: SystemLanguageModel.default,
            tools: search.gatewayTools()
        ) {
            Instructions("You are a helpful assistant.")
        }

        let response = try await session.respond(
            to: "What is the weather in Tokyo right now?",
            options: GenerationOptions(maximumResponseTokens: 512)
        )

        let dump = Self.dumpTranscript(session.transcript)
        print(dump)

        #expect(!response.content.isEmpty, "Empty response.\n\n=== Transcript ===\n\(dump)")

        let instructionEntries = session.transcript.compactMap { entry -> Transcript.Instructions? in
            if case .instructions(let instructions) = entry {
                return instructions
            }
            return nil
        }
        guard let instructions = instructionEntries.first else {
            Issue.record("Expected an instructions transcript entry.\n\n=== Transcript ===\n\(dump)")
            return
        }

        let initialToolDefinitions = instructions.toolDefinitions
        let initialToolNames = initialToolDefinitions.map(\.name)
        #expect(initialToolNames == ["ToolSearch"], "Initial tool definitions should expose only ToolSearch, got: \(initialToolNames).\n\n=== Transcript ===\n\(dump)")

        _ = try #require(initialToolDefinitions.first)
        let toolSearchSchemaDump = Self.schemaSummary(search.parameters)
        print("""
        === ToolSearch Initial Definition Summary ===
        toolNames: \(initialToolNames)
        schema:
        \(toolSearchSchemaDump)
        === End ToolSearch Initial Definition Summary ===
        """)
        #expect(toolSearchSchemaDump.contains("operation"), "ToolSearch schema should contain the gateway operation field.\n\n=== ToolSearch schema ===\n\(toolSearchSchemaDump)")
        #expect(toolSearchSchemaDump.contains("arguments"), "ToolSearch schema should contain the gateway arguments field.\n\n=== ToolSearch schema ===\n\(toolSearchSchemaDump)")
        #expect(!toolSearchSchemaDump.contains("city"), "Initial ToolSearch schema must not contain Weather.city.\n\n=== ToolSearch schema ===\n\(toolSearchSchemaDump)")
        #expect(!toolSearchSchemaDump.contains("The city name"), "Initial ToolSearch schema must not contain Weather field descriptions.\n\n=== ToolSearch schema ===\n\(toolSearchSchemaDump)")

        let invokedToolNames: [String] = session.transcript.compactMap { entry in
            if case .toolOutput(let out) = entry { return out.toolName }
            return nil
        }

        #expect(
            invokedToolNames.contains("ToolSearch"),
            "Expected the model to call ToolSearch — got: \(invokedToolNames).\n\n=== Transcript ===\n\(dump)"
        )

        #expect(log.calls.contains("Tokyo"),
                "ToolSearch gateway did not dispatch to the inner Weather tool. Cities logged: \(log.calls).\n\n=== Transcript ===\n\(dump)")
    }

    @Test(
        "SystemLanguageModel completes ToolSearch through ToolRuntime middleware",
        .enabled(if: runFoundationModelsToolSearchE2E),
        .timeLimit(.minutes(3))
    )
    func progressiveDisclosureViaToolRuntime() async throws {
        let weatherLog = CallLog()
        let middlewareLog = MiddlewareLog()
        let search = ToolSearchTool {
            WeatherTool(log: weatherLog)
        }

        var configuration = ToolRuntimeConfiguration.empty
        configuration.use(RecordingMiddleware(log: middlewareLog))
        configuration.register(search)
        let runtime = ToolRuntime(configuration: configuration)

        let session = LanguageModelSession(
            model: SystemLanguageModel.default,
            tools: runtime.publicTools()
        ) {
            Instructions("You are a helpful assistant.")
        }

        let response = try await session.respond(
            to: "What is the weather in Tokyo right now?",
            options: GenerationOptions(maximumResponseTokens: 512)
        )

        let dump = Self.dumpTranscript(session.transcript)
        print(dump)

        #expect(!response.content.isEmpty, "Empty response.\n\n=== Transcript ===\n\(dump)")

        let instructionEntries = session.transcript.compactMap { entry -> Transcript.Instructions? in
            if case .instructions(let instructions) = entry {
                return instructions
            }
            return nil
        }
        guard let instructions = instructionEntries.first else {
            Issue.record("Expected an instructions transcript entry.\n\n=== Transcript ===\n\(dump)")
            return
        }

        let initialToolNames = instructions.toolDefinitions.map(\.name)
        #expect(initialToolNames == ["ToolSearch"], "Runtime public tools should expose only ToolSearch, got: \(initialToolNames).\n\n=== Transcript ===\n\(dump)")

        #expect(weatherLog.calls.contains("Tokyo"),
                "ToolRuntime-backed ToolSearch did not dispatch to Weather. Cities logged: \(weatherLog.calls).\n\n=== Transcript ===\n\(dump)")

        #expect(
            middlewareLog.calls.contains("ToolSearch"),
            "Middleware did not observe the public ToolSearch call. Middleware calls: \(middlewareLog.calls).\n\n=== Transcript ===\n\(dump)"
        )
        #expect(
            middlewareLog.calls.contains("Weather"),
            "Middleware did not observe the hidden inner Weather call. Middleware calls: \(middlewareLog.calls).\n\n=== Transcript ===\n\(dump)"
        )
    }

    // MARK: - Transcript Diagnostics

    static func schemaSummary(_ schema: GenerationSchema) -> String {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        do {
            let data = try encoder.encode(schema)
            guard let text = String(data: data, encoding: .utf8) else {
                return String(describing: schema)
            }
            return text
        } catch {
            return String(describing: schema)
        }
    }

    static func dumpTranscript(_ transcript: Transcript) -> String {
        var lines: [String] = []
        for (index, entry) in transcript.enumerated() {
            switch entry {
            case .instructions(let i):
                lines.append("[\(index)] INSTRUCTIONS")
                lines.append(contentsOf: textLines(from: i.segments, indent: "    "))
            case .prompt(let p):
                lines.append("[\(index)] PROMPT")
                lines.append(contentsOf: textLines(from: p.segments, indent: "    "))
            case .toolCalls(let calls):
                lines.append("[\(index)] TOOL CALLS")
                for call in calls {
                    lines.append("    → \(call.toolName)(\(call.arguments.jsonString))")
                }
            case .toolOutput(let out):
                lines.append("[\(index)] TOOL OUTPUT: \(out.toolName)")
                lines.append(contentsOf: textLines(from: out.segments, indent: "    "))
            case .response(let r):
                lines.append("[\(index)] RESPONSE")
                lines.append(contentsOf: textLines(from: r.segments, indent: "    "))
            case .reasoning(let reasoning):
                lines.append("[\(index)] REASONING")
                lines.append(contentsOf: textLines(from: reasoning.segments, indent: "    "))
            @unknown default:
                lines.append("[\(index)] UNKNOWN entry")
            }
        }
        return lines.joined(separator: "\n")
    }

    private static func textLines(from segments: [Transcript.Segment], indent: String) -> [String] {
        segments.flatMap { segment -> [String] in
            switch segment {
            case .text(let t):
                return t.content.split(separator: "\n", omittingEmptySubsequences: false)
                    .map { "\(indent)\($0)" }
            case .structure(let s):
                return ["\(indent)<structure> \(s.content)"]
            case .attachment(let attachment):
                return ["\(indent)<attachment> \(attachment)"]
            case .custom(let custom):
                return ["\(indent)<custom> \(custom)"]
            @unknown default:
                return ["\(indent)<unknown segment>"]
            }
        }
    }

}

#endif
