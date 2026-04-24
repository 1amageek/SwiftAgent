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
