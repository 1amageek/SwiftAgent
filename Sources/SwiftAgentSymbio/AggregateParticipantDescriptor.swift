//
//  AggregateParticipantDescriptor.swift
//  SwiftAgentSymbio
//

public struct AggregateParticipantDescriptor: Identifiable, Sendable, Codable, Hashable {
    public let id: ParticipantID
    public let displayName: String?
    public let kind: AggregateKind
    public let members: [AggregateMember]
    public let rollupPolicy: RollupPolicy
    public let metadata: [String: String]

    public init(
        id: ParticipantID,
        displayName: String? = nil,
        kind: AggregateKind,
        members: [AggregateMember],
        rollupPolicy: RollupPolicy,
        metadata: [String: String] = [:]
    ) {
        self.id = id
        self.displayName = displayName
        self.kind = kind
        self.members = members
        self.rollupPolicy = rollupPolicy
        self.metadata = metadata
    }
}
