import Foundation

public enum SymbioRuntimeError: Error, LocalizedError, Sendable {
    case invalidLifecycle(String)
    case duplicateParticipant(ParticipantID)
    case localCatalogTransitionInProgress
    case participantTransitionInProgress(ParticipantID)
    case invalidParticipantHandle(ParticipantID)
    case participantUnavailable(ParticipantID)
    case participantBlocked(ParticipantID)
    case participantNotFound(ParticipantID)
    case participantClaimRejected(peerID: TransportPeerID, reason: String)
    case participantIdentityConflict(ParticipantID)
    case invalidVerifiedBinding(String)
    case policyApprovalRequired(Set<String>)
    case policyDenied([String])
    case inboundInvocationDenied(String)
    case routeRejected(String)
    case invocationFailed(code: SymbioInvocationFailureCode, message: String)
    case invocationResponseMismatch(expected: String, actual: String)
    case invalidConfiguration(String)
    case invalidExecutionBudget
    case invalidParticipantDescriptor(ParticipantID, reason: String)
    case invalidAggregateDescriptor(ParticipantID, reason: String)
    case runtimeIdentityAdvertisesCapabilities
    case deadlineExceeded
    case noLinkAvailable
    case cannotForgetLocal(ParticipantID)
    case cannotForgetConnected(ParticipantID)
    case changeSubscriberOverflow
    case linkEndedUnexpectedly
    case linkFailed(String)
    case publicationFailed(participantID: ParticipantID, reason: String)
    case withdrawalFailed(participantID: ParticipantID, reason: String)
    case cleanupFailed([String])

    public var errorDescription: String? {
        switch self {
        case .invalidLifecycle(let reason):
            return "Invalid Symbio lifecycle: \(reason)"
        case .duplicateParticipant(let id):
            return "Participant '\(id.rawValue)' is already registered"
        case .localCatalogTransitionInProgress:
            return "Another local participant catalog transition is in progress"
        case .participantTransitionInProgress(let id):
            return "Participant '\(id.rawValue)' already has a lifecycle transition in progress"
        case .invalidParticipantHandle(let id):
            return "Participant handle for '\(id.rawValue)' is invalid or no longer owned by this runtime"
        case .participantUnavailable(let id):
            return "Participant '\(id.rawValue)' is not available"
        case .participantBlocked(let id):
            return "Participant '\(id.rawValue)' is blocked in this local runtime view"
        case .participantNotFound(let id):
            return "Participant '\(id.rawValue)' was not found in this runtime view"
        case .participantClaimRejected(let peerID, let reason):
            return "Participant claim from transport peer '\(peerID.rawValue)' was rejected: \(reason)"
        case .participantIdentityConflict(let id):
            return "Participant identity '\(id.rawValue)' conflicts with an existing binding"
        case .invalidVerifiedBinding(let reason):
            return "Participant verifier returned an invalid binding: \(reason)"
        case .policyApprovalRequired(let policies):
            return "Policy approval is required: \(policies.sorted().joined(separator: ", "))"
        case .policyDenied(let reasons):
            return "Policy denied: \(reasons.joined(separator: ", "))"
        case .inboundInvocationDenied(let reason):
            return "Inbound invocation denied: \(reason)"
        case .routeRejected(let reason):
            return "Route rejected: \(reason)"
        case .invocationFailed(let code, let message):
            return "Invocation failed (\(code.rawValue)): \(message)"
        case .invocationResponseMismatch(let expected, let actual):
            return "Invocation response mismatch: expected '\(expected)', received '\(actual)'"
        case .invalidConfiguration(let reason):
            return "Invalid Symbio runtime configuration: \(reason)"
        case .invalidExecutionBudget:
            return "Execution budget must be greater than zero"
        case .invalidParticipantDescriptor(let id, let reason):
            return "Participant descriptor '\(id.rawValue)' is invalid: \(reason)"
        case .invalidAggregateDescriptor(let id, let reason):
            return "Aggregate descriptor '\(id.rawValue)' is invalid: \(reason)"
        case .runtimeIdentityAdvertisesCapabilities:
            return "The runtime control identity cannot advertise executable capabilities without an endpoint"
        case .deadlineExceeded:
            return "Invocation deadline exceeded"
        case .noLinkAvailable:
            return "No remote Symbio link is available"
        case .cannotForgetLocal(let id):
            return "Cannot forget local participant '\(id.rawValue)'"
        case .cannotForgetConnected(let id):
            return "Cannot forget connected participant '\(id.rawValue)'"
        case .changeSubscriberOverflow:
            return "A Symbio change subscriber did not consume events within its bounded capacity"
        case .linkEndedUnexpectedly:
            return "The Symbio link ended while the runtime was active"
        case .linkFailed(let reason):
            return "The Symbio link failed: \(reason)"
        case .publicationFailed(let participantID, let reason):
            return "Failed to publish participant '\(participantID.rawValue)': \(reason)"
        case .withdrawalFailed(let participantID, let reason):
            return "Failed to withdraw participant '\(participantID.rawValue)': \(reason)"
        case .cleanupFailed(let failures):
            return "Symbio cleanup failed: \(failures.joined(separator: "; "))"
        }
    }
}
