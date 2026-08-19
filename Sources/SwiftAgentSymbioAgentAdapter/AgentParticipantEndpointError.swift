import Foundation

public enum AgentParticipantEndpointError: Error, LocalizedError, Sendable {
    case unsupportedCapability(String)
    case duplicateCapability(String)
    case duplicatePerception
    case reservedCapabilityNamespace(String)
    case endpointUnavailable

    public var errorDescription: String? {
        switch self {
        case .unsupportedCapability(let capability):
            return "Agent does not provide capability '\(capability)'"
        case .duplicateCapability(let capability):
            return "Agent declares capability '\(capability)' more than once"
        case .duplicatePerception:
            return "Agent declares the same perception identifier more than once"
        case .reservedCapabilityNamespace(let capability):
            return "Agent action capability '\(capability)' uses the reserved perception namespace"
        case .endpointUnavailable:
            return "Agent participant endpoint is shutting down"
        }
    }
}
