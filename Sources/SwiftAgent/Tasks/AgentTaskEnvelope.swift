//
//  AgentTaskEnvelope.swift
//  SwiftAgent
//

import Foundation

/// Canonical work unit for running work across sessions and agents.
///
/// `RunRequest` remains the transport-level representation of one turn.
/// `AgentTaskEnvelope` wraps that turn with task identity, correlation,
/// requested assignee constraints, and provenance.
public struct AgentTaskEnvelope: Identifiable, Sendable, Codable {
    /// Unique task identifier.
    public let id: String

    /// Correlation identifier shared by related tasks.
    public let correlationID: String

    /// Agent or client that requested the task.
    public let requesterID: String?

    /// Requested assignee, if routing has already selected one.
    public let assigneeID: String?

    /// Session identifier used by the local runner.
    public let sessionID: String

    /// Turn identifier used by the local runner.
    public let turnID: String

    /// Provenance relationship for tracing.
    public let relation: AgentTaskRelation

    /// The turn input.
    public let input: InputPayload

    /// Additional context for the turn.
    public let context: ContextPayload?

    /// Requested task policy.
    public let policy: AgentTaskPolicy

    /// Transport- and coordinator-level metadata.
    public let metadata: [String: String]

    /// Creation timestamp.
    public let createdAt: Date

    public init(
        id: String = UUID().uuidString,
        correlationID: String = UUID().uuidString,
        requesterID: String? = nil,
        assigneeID: String? = nil,
        sessionID: String = UUID().uuidString,
        turnID: String = UUID().uuidString,
        relation: AgentTaskRelation = .root,
        input: InputPayload,
        context: ContextPayload? = nil,
        policy: AgentTaskPolicy = AgentTaskPolicy(),
        metadata: [String: String] = [:],
        createdAt: Date = Date()
    ) {
        self.id = id
        self.correlationID = correlationID
        self.requesterID = requesterID
        self.assigneeID = assigneeID
        self.sessionID = sessionID
        self.turnID = turnID
        self.relation = relation
        self.input = input
        self.context = context
        self.policy = policy
        self.metadata = metadata
        self.createdAt = createdAt
    }

    public init(
        runRequest: RunRequest,
        id: String = UUID().uuidString,
        correlationID: String = UUID().uuidString,
        requesterID: String? = nil,
        assigneeID: String? = nil,
        relation: AgentTaskRelation = .root,
        policy: AgentTaskPolicy? = nil,
        createdAt: Date = Date()
    ) {
        self.init(
            id: id,
            correlationID: correlationID,
            requesterID: requesterID,
            assigneeID: assigneeID,
            sessionID: runRequest.sessionID,
            turnID: runRequest.turnID,
            relation: relation,
            input: runRequest.input,
            context: runRequest.context,
            policy: policy ?? AgentTaskPolicy(execution: runRequest.policy ?? ExecutionPolicy()),
            metadata: runRequest.metadata ?? [:],
            createdAt: createdAt
        )
    }

    /// Converts the envelope to the transport-level run request used by
    /// existing session primitives.
    public var runRequest: RunRequest {
        RunRequest(
            sessionID: sessionID,
            turnID: turnID,
            input: input,
            context: context,
            policy: policy.execution,
            metadata: enrichedMetadata
        )
    }

    /// Metadata with task identity attached for downstream runtime consumers.
    public var enrichedMetadata: [String: String] {
        var result = metadata
        result["taskID"] = id
        result["correlationID"] = correlationID
        if let requesterID {
            result["requesterID"] = requesterID
        }
        if let assigneeID {
            result["assigneeID"] = assigneeID
        }
        return result
    }
}
