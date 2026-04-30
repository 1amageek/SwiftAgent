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
            } else if promptText.contains("fail beta") {
                throw AgentWorkflowE2EError.scriptedFailure
            } else if promptText.contains("produce beta") {
                content = "beta result"
            } else if promptText.contains("synthesize selected")
                && promptText.contains("alpha result")
                && !promptText.contains("beta result") {
                content = "selected alpha only"
            } else if promptText.contains("summarize after failure")
                && promptText.contains("alpha result")
                && promptText.contains(#""status":"failed""#) {
                content = "partial failure summarized"
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

    enum AgentWorkflowE2EError: Error {
        case scriptedFailure
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

    @Test("Workflow continues after failed step when failFast is disabled", .timeLimit(.minutes(1)))
    func workflowContinuesAfterFailedStepWhenFailFastIsDisabled() async throws {
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
            id: "workflow-partial-failure",
            correlationID: "workflow-partial-failure-correlation",
            steps: [
                AgentWorkflowStep(
                    id: "alpha",
                    envelope: AgentTaskEnvelope(
                        correlationID: "workflow-partial-failure-correlation",
                        input: .text("produce alpha")
                    )
                ),
                AgentWorkflowStep(
                    id: "beta",
                    envelope: AgentTaskEnvelope(
                        correlationID: "workflow-partial-failure-correlation",
                        input: .text("fail beta")
                    )
                ),
                AgentWorkflowStep(
                    id: "synthesis",
                    envelope: AgentTaskEnvelope(
                        correlationID: "workflow-partial-failure-correlation",
                        input: .text("summarize after failure")
                    ),
                    access: .allPrevious,
                    role: .synthesize
                ),
            ],
            finalStepID: "synthesis",
            policy: AgentWorkflowPolicy(failFast: false)
        )

        let result = try await executor.execute(plan)

        #expect(result.status == .partiallyCompleted)
        #expect(result.finalOutput == "partial failure summarized")
        #expect(result.stepResults.map(\.stepID) == ["alpha", "beta", "synthesis"])
        #expect(result.stepResults.map(\.status) == [.completed, .failed, .completed])
        #expect(model.transcripts.count == 3)
    }
}

#endif
