//
//  AgentTaskEnvelopeTests.swift
//  SwiftAgent
//

import Foundation
import Testing
@testable import SwiftAgent

@Suite("AgentTaskEnvelope")
struct AgentTaskEnvelopeTests {

    @Test("Envelope wraps RunRequest and enriches metadata")
    func envelopeWrapsRunRequest() throws {
        let request = RunRequest(
            sessionID: "session-1",
            turnID: "turn-1",
            input: .text("summarize this"),
            context: ContextPayload(steering: ["be concise"]),
            policy: ExecutionPolicy(maxToolCalls: 3, allowInteractiveApproval: false),
            metadata: ["source": "test"]
        )

        let envelope = AgentTaskEnvelope(
            runRequest: request,
            id: "task-1",
            correlationID: "correlation-1",
            requesterID: "requester-1",
            assigneeID: "assignee-1",
            relation: .delegated(parentTaskID: "parent-1")
        )

        let roundTrip = envelope.runRequest

        #expect(roundTrip.sessionID == "session-1")
        #expect(roundTrip.turnID == "turn-1")
        #expect(roundTrip.metadata?["source"] == "test")
        #expect(roundTrip.metadata?["taskID"] == "task-1")
        #expect(roundTrip.metadata?["correlationID"] == "correlation-1")
        #expect(roundTrip.metadata?["requesterID"] == "requester-1")
        #expect(roundTrip.metadata?["assigneeID"] == "assignee-1")

        if case .text(let text) = roundTrip.input {
            #expect(text == "summarize this")
        } else {
            Issue.record("Expected text input")
        }
    }

    @Test("Envelope is codable across process boundaries")
    func envelopeIsCodable() throws {
        let envelope = AgentTaskEnvelope(
            id: "task-2",
            correlationID: "correlation-2",
            requesterID: "local-agent",
            sessionID: "session-2",
            turnID: "turn-2",
            relation: .peerRequest,
            input: .text("inspect workspace"),
            policy: AgentTaskPolicy(
                priority: .high,
                requiredCapabilities: ["filesystem.read"],
                toolScope: .listed(["Read", "Grep"])
            )
        )

        let data = try JSONEncoder().encode(envelope)
        let decoded = try JSONDecoder().decode(AgentTaskEnvelope.self, from: data)

        #expect(decoded.id == "task-2")
        #expect(decoded.correlationID == "correlation-2")
        #expect(decoded.requesterID == "local-agent")
        #expect(decoded.sessionID == "session-2")
        #expect(decoded.turnID == "turn-2")
        #expect(decoded.policy.priority == .high)
        #expect(decoded.policy.requiredCapabilities == ["filesystem.read"])

        if case .text(let text) = decoded.input {
            #expect(text == "inspect workspace")
        } else {
            Issue.record("Expected text input")
        }
    }
}
