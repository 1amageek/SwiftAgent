//
//  AgentSessionRunnerTests.swift
//  SwiftAgent
//

import Foundation
import Synchronization
import Testing
@testable import SwiftAgent

#if OpenFoundationModels
import OpenFoundationModels

@Suite("AgentSessionRunner")
struct AgentSessionRunnerTests {

    final class EventLog: Sendable {
        private let storage = Mutex<[AgentTaskEvent]>([])

        var events: [AgentTaskEvent] {
            storage.withLock { $0 }
        }

        func append(_ event: AgentTaskEvent) {
            storage.withLock { $0.append(event) }
        }
    }

    actor CancellationProbe {
        private var entered = false
        private var cancelled = false

        func markEntered() {
            entered = true
        }

        func markCancelled() {
            cancelled = true
        }

        func waitUntilEntered() async -> Bool {
            let deadline = ContinuousClock.now.advanced(by: .seconds(1))
            while !entered {
                if ContinuousClock.now >= deadline {
                    return false
                }
                do {
                    try await Task.sleep(for: .milliseconds(10))
                } catch {
                    return false
                }
            }
            return true
        }

        func waitUntilCancelled() async -> Bool {
            let deadline = ContinuousClock.now.advanced(by: .seconds(1))
            while !cancelled {
                if ContinuousClock.now >= deadline {
                    return false
                }
                do {
                    try await Task.sleep(for: .milliseconds(10))
                } catch {
                    return false
                }
            }
            return true
        }
    }

    @Test("Runner emits task and run lifecycle events", .timeLimit(.minutes(1)))
    func runnerEmitsLifecycleEvents() async throws {
        let log = EventLog()
        let configuration = AgentSessionRunnerConfiguration(
            runtimeConfiguration: .empty,
            eventHandler: { event in
                log.append(event)
            }
        ) {
            Instructions("Return the transformed result.")
        } step: {
            Transform { (_: Prompt) in
                "runner output"
            }
        }

        let runner = AgentSessionRunner(
            model: MockLanguageModel(),
            configuration: configuration
        )
        let envelope = AgentTaskEnvelope(
            id: "task-runner-1",
            correlationID: "correlation-runner-1",
            sessionID: "session-runner-1",
            turnID: "turn-runner-1",
            input: .text("hello")
        )

        let result = try await runner.run(envelope)

        #expect(result.taskID == "task-runner-1")
        #expect(result.correlationID == "correlation-runner-1")
        #expect(result.status == .completed)
        #expect(result.finalOutput == "runner output")

        let events = log.events
        #expect(events.contains { event in
            if case .taskStarted(let started) = event {
                return started.taskID == "task-runner-1"
            }
            return false
        })
        #expect(events.contains { event in
            if case .runEvent(let runEvent) = event,
               case .runStarted(let started) = runEvent.event {
                return started.sessionID == "session-runner-1"
            }
            return false
        })
        #expect(events.contains { event in
            if case .runEvent(let runEvent) = event,
               case .tokenDelta(let token) = runEvent.event {
                return token.accumulated == "runner output" && token.isComplete
            }
            return false
        })
        #expect(events.contains { event in
            if case .runEvent(let runEvent) = event,
               case .runCompleted(let completed) = runEvent.event {
                return completed.status == .completed
            }
            return false
        })
        #expect(events.contains { event in
            if case .taskCompleted(let completed) = event {
                return completed.result.status == .completed
            }
            return false
        })
    }

    @Test("Runner maps execution timeout to timedOut status", .timeLimit(.minutes(1)))
    func runnerMapsExecutionTimeout() async throws {
        let log = EventLog()
        let configuration = AgentSessionRunnerConfiguration(
            runtimeConfiguration: .empty,
            eventHandler: { event in
                log.append(event)
            }
        ) {
            Instructions("Run slowly.")
        } step: {
            Transform { (_: Prompt) in
                try await Task.sleep(for: .seconds(5))
                return "too late"
            }
        }

        let runner = AgentSessionRunner(
            model: MockLanguageModel(),
            configuration: configuration
        )
        let envelope = AgentTaskEnvelope(
            id: "task-runner-timeout",
            correlationID: "correlation-runner-timeout",
            input: .text("slow"),
            policy: AgentTaskPolicy(
                execution: ExecutionPolicy(timeout: .milliseconds(1))
            )
        )

        let result = try await runner.run(envelope)

        #expect(result.status == .timedOut)
        #expect(result.finalOutput == nil)
        #expect(log.events.contains { event in
            if case .runEvent(let runEvent) = event,
               case .runCompleted(let completed) = runEvent.event {
                return completed.status == .timedOut
            }
            return false
        })
    }

    @Test("Stream cancellation cancels the running task", .timeLimit(.minutes(1)))
    func streamCancellationCancelsRunningTask() async throws {
        let probe = CancellationProbe()
        let configuration = AgentSessionRunnerConfiguration(
            runtimeConfiguration: .empty
        ) {
            Instructions("Wait until cancelled.")
        } step: {
            Transform { (_: Prompt) in
                await probe.markEntered()
                return try await withTaskCancellationHandler {
                    while true {
                        try await Task.sleep(for: .seconds(1))
                    }
                    return "unreachable"
                } onCancel: {
                    Task {
                        await probe.markCancelled()
                    }
                }
            }
        }

        let runner = AgentSessionRunner(
            model: MockLanguageModel(),
            configuration: configuration
        )
        let envelope = AgentTaskEnvelope(input: .text("start"))

        do {
            let stream = runner.stream(envelope)
            var iterator = stream.makeAsyncIterator()
            _ = try await iterator.next()
            #expect(await probe.waitUntilEntered())
        }

        #expect(await probe.waitUntilCancelled())
    }

    @Test("Turn timeout cancels token without waiting for non-cooperative operation", .timeLimit(.minutes(1)))
    func turnTimeoutCancelsTokenWithoutWaiting() async throws {
        let configuration = AgentSessionRunnerConfiguration(
            runtimeConfiguration: .empty
        ) {
            Instructions("Never finish.")
        } step: {
            Transform { (_: Prompt) in
                try await withCheckedThrowingContinuation { continuation in
                    Task.detached {
                        do {
                            try await Task.sleep(for: .seconds(2))
                            continuation.resume(returning: "late")
                        } catch {
                        }
                    }
                }
            }
        }
        let runtime = ToolRuntime(configuration: .empty)
        let languageModelSession = LanguageModelSession(
            model: MockLanguageModel(),
            tools: runtime.publicTools()
        ) {
            configuration.instructions()
        }
        let conversation = Conversation(languageModelSession: languageModelSession) {
            configuration.step()
        }
        let executor = AgentTurnExecutor(conversation: conversation) { _ in }
        let token = TurnCancellationToken()
        let request = RunRequest(
            input: .text("start"),
            policy: ExecutionPolicy(timeout: .milliseconds(10))
        )

        let start = ContinuousClock.now
        let result = await executor.execute(
            request: request,
            cancellationToken: token
        )
        let elapsed = ContinuousClock.now - start

        #expect(result.status == .timedOut)
        #expect(token.isCancelled)
        #expect(elapsed < .milliseconds(500))
    }
}

#endif
