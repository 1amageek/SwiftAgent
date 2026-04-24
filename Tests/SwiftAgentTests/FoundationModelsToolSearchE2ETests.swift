//
//  FoundationModelsToolSearchE2ETests.swift
//  SwiftAgent
//
//  End-to-end progressive disclosure flow exercised against the real
//  on-device SystemLanguageModel. Skipped automatically when Apple
//  Intelligence is not available on the host.
//

import Testing
import Foundation
import Synchronization
@testable import SwiftAgent

#if !OpenFoundationModels
import FoundationModels

@Suite("FoundationModels ToolSearch E2E", .serialized)
struct FoundationModelsToolSearchE2ETests {

    // MARK: - Instrumented Weather Tool

    final class CallLog: Sendable {
        let cities: Mutex<[String]> = Mutex([])
        var calls: [String] { cities.withLock { $0 } }
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
        .enabled(if: SystemLanguageModel.default.isAvailable),
        .timeLimit(.minutes(2))
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

        let response = try await session.respond(to: "What is the weather in Tokyo right now?")

        let dump = Self.dumpTranscript(session.transcript)
        print(dump)

        #expect(!response.content.isEmpty, "Empty response.\n\n=== Transcript ===\n\(dump)")

        let instructions = try #require(session.transcript.compactMap { entry -> Transcript.Instructions? in
            if case .instructions(let instructions) = entry {
                return instructions
            }
            return nil
        }.first)

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
        #expect(toolSearchSchemaDump.contains("argumentsJSON"), "ToolSearch schema should contain the gateway argumentsJSON field.\n\n=== ToolSearch schema ===\n\(toolSearchSchemaDump)")
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

    // MARK: - Transcript Diagnostics

    static func schemaSummary(_ schema: GenerationSchema) -> String {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        guard let data = try? encoder.encode(schema),
              let text = String(data: data, encoding: .utf8) else {
            return String(describing: schema)
        }
        return text
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
            @unknown default:
                return ["\(indent)<unknown segment>"]
            }
        }
    }

}

#endif
