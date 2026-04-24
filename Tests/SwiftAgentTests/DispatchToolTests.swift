//
//  DispatchToolTests.swift
//  SwiftAgent
//

import Foundation
import Synchronization
import Testing
import SwiftAgent
@testable import AgentTools

#if OpenFoundationModels
import OpenFoundationModels
@_spi(Internal) import OpenFoundationModelsCore

@Suite("DispatchTool")
struct DispatchToolTests {

    final class ToolCallLog: Sendable {
        private let storage = Mutex<[String]>([])

        var calls: [String] {
            storage.withLock { $0 }
        }

        func append(_ toolName: String) {
            storage.withLock { $0.append(toolName) }
        }
    }

    struct RecordingMiddleware: ToolMiddleware {
        let log: ToolCallLog

        func handle(_ context: ToolContext, next: @escaping Next) async throws -> ToolResult {
            log.append(context.toolName)
            return try await next(context)
        }
    }

    final class NotebookCallingModel: LanguageModel, Sendable {
        private let storage = Mutex<[Transcript]>([])

        var transcripts: [Transcript] {
            storage.withLock { $0 }
        }

        var isAvailable: Bool { true }

        func supports(locale: Locale) -> Bool { true }

        func generate(
            transcript: Transcript,
            options: GenerationOptions?
        ) async throws -> Transcript.Entry {
            storage.withLock { $0.append(transcript) }

            let notebookOutputs = transcript.reduce(into: 0) { count, entry in
                if case .toolOutput(let output) = entry, output.toolName == "Notebook" {
                    count += 1
                }
            }

            if notebookOutputs == 0 {
                return .toolCalls(Transcript.ToolCalls([
                    Transcript.ToolCall(
                        id: UUID().uuidString,
                        toolName: "Notebook",
                        arguments: GeneratedContent(properties: [
                            "operation": "write",
                            "key": "dispatch-result",
                            "value": "from subtask",
                            "offset": 0,
                            "limit": 0,
                        ])
                    )
                ]))
            }

            return .response(Transcript.Response(
                id: UUID().uuidString,
                assetIDs: [],
                segments: [.text(Transcript.TextSegment(
                    id: UUID().uuidString,
                    content: "subtask complete"
                ))]
            ))
        }

        func stream(
            transcript: Transcript,
            options: GenerationOptions?
        ) -> AsyncThrowingStream<Transcript.Entry, Error> {
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

    @Test("Sub-session tools execute through ToolRuntime middleware")
    func subSessionToolsUseRuntimeMiddleware() async throws {
        let model = NotebookCallingModel()
        let notebook = NotebookStorage()
        let log = ToolCallLog()

        var runtimeConfiguration = ToolRuntimeConfiguration.empty
        runtimeConfiguration.use(RecordingMiddleware(log: log))

        let dispatch = DispatchTool(
            languageModel: model,
            notebookStorage: notebook,
            maxDepth: 0,
            runtimeConfiguration: runtimeConfiguration
        )

        let output = try await dispatch.call(arguments: DispatchInput(
            operation: "query",
            task: "Write the subtask result to Notebook."
        ))

        #expect(output.success)
        #expect(output.content == "subtask complete")
        #expect(output.sessionIDs.count == 1)
        #expect(notebook.read(key: "dispatch-result") == "from subtask")
        #expect(log.calls == ["Notebook"])
    }
}

#endif
