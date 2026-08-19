import SwiftAgent

public enum AgentCapabilityNamespace {
    public static let perception = "agent.perception"
    public static let action = "agent.action"
}

extension Perception {
    public var capabilityIdentifier: String {
        "\(AgentCapabilityNamespace.perception).\(identifier)"
    }
}
