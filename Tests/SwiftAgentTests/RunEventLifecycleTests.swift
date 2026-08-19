//
//  RunEventLifecycleTests.swift
//  SwiftAgent
//

import Foundation
import Synchronization
import Testing
@testable import SwiftAgent

@Suite("RunEvent Lifecycle")
struct RunEventLifecycleTests {
    final class EventRecorder: Sendable {
        private let storage = Mutex<[RunEvent]>([])

        var events: [RunEvent] {
            storage.withLock { $0 }
        }

        func append(_ event: RunEvent) {
            storage.withLock { $0.append(event) }
        }
    }

    final class ConcurrentDeliveryProbe: Sendable {
        private struct State: Sendable {
            var activeHandlers = 0
            var maximumActiveHandlers = 0
            var handledEvents = 0
        }

        private let state = Mutex(State())

        var snapshot: (
            maximumActiveHandlers: Int,
            handledEvents: Int
        ) {
            state.withLock {
                (
                    maximumActiveHandlers: $0.maximumActiveHandlers,
                    handledEvents: $0.handledEvents
                )
            }
        }

        func handle(_ event: RunEvent) async {
            state.withLock {
                $0.activeHandlers += 1
                $0.maximumActiveHandlers = max(
                    $0.maximumActiveHandlers,
                    $0.activeHandlers
                )
            }
            for _ in 0..<16 {
                await Task.yield()
            }
            state.withLock {
                $0.activeHandlers -= 1
                $0.handledEvents += 1
            }
        }
    }

    @Test("EventEmittingMiddleware emits typed tool lifecycle events and compatibility events")
    func eventMiddlewareEmitsLifecycleEvents() async throws {
        let recorder = EventRecorder()
        let sink = EventSink { event in
            recorder.append(event)
        }
        let middleware = EventEmittingMiddleware()
        let context = ToolContext(toolName: "Echo", arguments: #"{"value":"hi"}"#)
        let sessionContext = AgentSessionContext(sessionID: "session-1", turnID: "turn-1")

        _ = try await AgentSessionContext.$current.withValue(sessionContext) {
            try await EventSinkContext.withValue(sink) {
                try await middleware.handle(context) { _ in
                    .success("ok", duration: .zero)
                }
            }
        }

        let eventKinds = recorder.events.map(Self.kind)
        #expect(eventKinds == ["toolStarted", "toolCall", "toolFinished", "toolResult"])

        let started = try #require(recorder.events.compactMap { event -> RunEvent.ToolCallEvent? in
            if case .toolStarted(let payload) = event { return payload }
            return nil
        }.first)
        #expect(started.toolName == "Echo")
        #expect(started.sessionID == "session-1")
        #expect(started.turnID == "turn-1")

        let finished = try #require(recorder.events.compactMap { event -> RunEvent.ToolResultEvent? in
            if case .toolFinished(let payload) = event { return payload }
            return nil
        }.first)
        #expect(finished.toolName == "Echo")
        #expect(finished.output == "ok")
        #expect(finished.success)
    }

    @Test("Tool lifecycle events are Codable")
    func lifecycleEventsAreCodable() throws {
        let started = RunEvent.toolStarted(RunEvent.ToolCallEvent(
            toolUseID: "tool-1",
            toolName: "Echo",
            arguments: #"{"value":"hi"}"#,
            sessionID: "session-1",
            turnID: "turn-1"
        ))
        let finished = RunEvent.toolFinished(RunEvent.ToolResultEvent(
            toolUseID: "tool-1",
            toolName: "Echo",
            output: "ok",
            success: true,
            duration: .zero,
            sessionID: "session-1",
            turnID: "turn-1"
        ))

        let encoder = JSONEncoder()
        let decoder = JSONDecoder()

        let decodedStarted = try decoder.decode(RunEvent.self, from: encoder.encode(started))
        let decodedFinished = try decoder.decode(RunEvent.self, from: encoder.encode(finished))

        if case .toolStarted(let payload) = decodedStarted {
            #expect(payload.toolName == "Echo")
        } else {
            Issue.record("Expected toolStarted")
        }

        if case .toolFinished(let payload) = decodedFinished {
            #expect(payload.output == "ok")
            #expect(payload.success)
        } else {
            Issue.record("Expected toolFinished")
        }
    }

    @Test("Concurrent emissions use one ordered handler chain")
    func concurrentEmissionsAreSerialized() async {
        let probe = ConcurrentDeliveryProbe()
        let sink = EventSink { event in
            await probe.handle(event)
        }

        await withTaskGroup(of: Void.self) { group in
            for index in 0..<32 {
                group.addTask {
                    await sink.emit(.warning(RunEvent.WarningEvent(
                        message: "event-\(index)",
                        sessionID: "session",
                        turnID: "turn"
                    )))
                }
            }
        }
        await sink.finish()

        let snapshot = probe.snapshot
        #expect(snapshot.maximumActiveHandlers == 1)
        #expect(snapshot.handledEvents == 32)
    }

    @Test("Finish is idempotent and rejects later emissions")
    func finishRejectsLateEmissions() async {
        let recorder = EventRecorder()
        let sink = EventSink { event in
            recorder.append(event)
        }
        let first = RunEvent.warning(RunEvent.WarningEvent(
            message: "before",
            sessionID: "session",
            turnID: "turn"
        ))
        let late = RunEvent.warning(RunEvent.WarningEvent(
            message: "after",
            sessionID: "session",
            turnID: "turn"
        ))

        await sink.emit(first)
        async let firstFinish: Void = sink.finish()
        async let secondFinish: Void = sink.finish()
        _ = await (firstFinish, secondFinish)
        await sink.emit(late)

        #expect(recorder.events.count == 1)
        #expect(Self.kind(recorder.events[0]) == "warning")
    }

    private static func kind(_ event: RunEvent) -> String {
        switch event {
        case .runStarted:
            "runStarted"
        case .tokenDelta:
            "tokenDelta"
        case .reasoningDelta:
            "reasoningDelta"
        case .toolCall:
            "toolCall"
        case .toolResult:
            "toolResult"
        case .toolStarted:
            "toolStarted"
        case .toolFinished:
            "toolFinished"
        case .approvalRequired:
            "approvalRequired"
        case .approvalResolved:
            "approvalResolved"
        case .warning:
            "warning"
        case .error:
            "error"
        case .runCompleted:
            "runCompleted"
        }
    }
}
