//
//  AgentWorkflowE2ETests.swift
//  SwiftAgent
//

import Foundation
import Synchronization
import Testing
@testable import SwiftAgent

#if OpenFoundationModels
import OpenFoundationModels

@Suite("AgentWorkflow E2E")
struct AgentWorkflowE2ETests {

    final class ContextAwareModel: LanguageModel, Sendable {
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

            let promptText = Self.promptText(in: transcript)
            let content: String
            if promptText.contains("produce alpha") {
                content = "alpha result"
            } else if promptText.contains("produce beta") {
                content = "beta result"
            } else if promptText.contains("synthesize selected")
                && promptText.contains("alpha result")
                && !promptText.contains("beta result") {
                content = "selected alpha only"
            } else {
                content = "unexpected context: \(promptText)"
            }

            return .response(Transcript.Response(
                id: UUID().uuidString,
                assetIDs: [],
                segments: [.text(Transcript.TextSegment(
                    id: UUID().uuidString,
                    content: content
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

        private static func promptText(in transcript: Transcript) -> String {
            var lines: [String] = []
            for entry in transcript {
                guard case .prompt(let prompt) = entry else {
                    continue
                }
                for segment in prompt.segments {
                    if case .text(let text) = segment {
                        lines.append(text.content)
                    }
                }
            }
            return lines.joined(separator: "\n")
        }
    }

    @Test("Workflow routes selected context through real model sessions", .timeLimit(.minutes(1)))
    func workflowRoutesSelectedContextThroughModelSessions() async throws {
        let model = ContextAwareModel()
        let configuration = AgentSessionRunnerConfiguration(
            runtimeConfiguration: .empty
        ) {
            Instructions("Execute each workflow step.")
        } step: {
            GenerateText<Prompt>()
        }

        let runner = AgentSessionRunner(model: model, configuration: configuration)
        let executor = AgentWorkflowExecutor(localRunner: runner)
        let plan = AgentWorkflowPlan(
            id: "workflow-e2e",
            correlationID: "workflow-e2e-correlation",
            steps: [
                AgentWorkflowStep(
                    id: "alpha",
                    envelope: AgentTaskEnvelope(
                        correlationID: "workflow-e2e-correlation",
                        input: .text("produce alpha")
                    )
                ),
                AgentWorkflowStep(
                    id: "beta",
                    envelope: AgentTaskEnvelope(
                        correlationID: "workflow-e2e-correlation",
                        input: .text("produce beta")
                    )
                ),
                AgentWorkflowStep(
                    id: "synthesis",
                    envelope: AgentTaskEnvelope(
                        correlationID: "workflow-e2e-correlation",
                        input: .text("synthesize selected")
                    ),
                    access: .steps(["alpha"]),
                    role: .synthesize
                ),
            ],
            finalStepID: "synthesis"
        )

        let result = try await executor.execute(plan)

        #expect(result.status == .completed)
        #expect(result.finalOutput == "selected alpha only")
        #expect(result.stepResults.map(\.stepID) == ["alpha", "beta", "synthesis"])
        #expect(model.transcripts.count == 3)
    }
}

#endif
