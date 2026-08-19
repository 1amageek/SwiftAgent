import Foundation
import SwiftAgentSymbio

public protocol AgentCapabilityProviding: Actor {
    nonisolated var capabilityContracts: Set<CapabilityContract> { get }

    func invokeCapability(
        _ data: Data,
        capability: String
    ) async throws -> Data?
}
