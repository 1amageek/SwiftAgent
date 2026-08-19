import Foundation
import NetworkingCore
import NetworkingFoundationCompat
import SwiftAgent
import SwiftAgentSymbio

public actor AgentParticipantEndpoint<Base: CommunicableAgent>: ParticipantEndpoint {
    private enum State {
        case running
        case shuttingDown
        case finished
    }

    public nonisolated let descriptor: ParticipantDescriptor

    private let agent: Base
    private let perceptionIdentifiers: Set<String>
    private let actionContracts: [String: CapabilityContract]
    private var state = State.running
    private var activeInvocationCount = 0
    private var drainWaiter: CheckedContinuation<Void, Never>?
    private var shutdownTask: Task<Void, Never>?

    public init(
        agent: Base,
        metadata: [String: String] = [:]
    ) throws {
        self.agent = agent

        let perceptions = agent.perceptions
        let perceptionContracts = perceptions.map { perception in
            CapabilityContract(
                id: perception.capabilityIdentifier,
                purpose: "Receive an agent perception",
                input: .typedPayload(schema: perception.identifier),
                sideEffectLevel: .localState
            )
        }
        let actionContracts = (agent as? any AgentCapabilityProviding)?
            .capabilityContracts ?? []
        let perceptionIdentifiers = Set(perceptions.map(\.identifier))
        guard perceptionIdentifiers.count == perceptions.count else {
            throw AgentParticipantEndpointError.duplicatePerception
        }
        self.perceptionIdentifiers = perceptionIdentifiers
        var actionContractsByID: [String: CapabilityContract] = [:]
        let perceptionPrefix = "\(AgentCapabilityNamespace.perception)."
        for contract in actionContracts {
            guard !contract.id.hasPrefix(perceptionPrefix) else {
                throw AgentParticipantEndpointError.reservedCapabilityNamespace(
                    contract.id
                )
            }
            guard actionContractsByID.updateValue(
                contract,
                forKey: contract.id
            ) == nil else {
                throw AgentParticipantEndpointError.duplicateCapability(
                    contract.id
                )
            }
        }
        self.actionContracts = actionContractsByID
        for contract in perceptionContracts {
            guard actionContractsByID[contract.id] == nil else {
                throw AgentParticipantEndpointError.duplicateCapability(
                    contract.id
                )
            }
        }
        let contracts = Set(perceptionContracts).union(actionContracts)

        self.descriptor = ParticipantDescriptor(
            id: agent.participantID,
            displayName: agent.displayName,
            kind: .agent,
            representations: Set(contracts.map(\.input)),
            capabilityContracts: contracts,
            selfClaims: contracts.map { contract in
                Claim(
                    subjectID: agent.participantID,
                    predicate: "symbio.affordance",
                    object: contract.id,
                    issuerID: agent.participantID
                )
            },
            metadata: metadata
        )
    }

    public func invoke(
        _ invocation: SymbioInvocation
    ) async throws -> OwnedBytes? {
        guard case .running = state else {
            throw AgentParticipantEndpointError.endpointUnavailable
        }
        try Task.checkCancellation()
        activeInvocationCount += 1
        defer { invocationFinished() }

        let envelope = invocation.envelope
        // Foundation Data is materialized only at the SwiftAgent adapter boundary.
        let input = Data(copying: envelope.arguments)
        let perceptionPrefix = "\(AgentCapabilityNamespace.perception)."

        if envelope.capability.hasPrefix(perceptionPrefix) {
            let perception = String(
                envelope.capability.dropFirst(perceptionPrefix.count)
            )
            guard perceptionIdentifiers.contains(perception),
                  envelope.representation == .typedPayload(
                    schema: perception
                  ) else {
                throw AgentParticipantEndpointError.unsupportedCapability(
                    envelope.capability
                )
            }
            let result = try await agent.receive(input, perception: perception)
            try Task.checkCancellation()
            return result.map { OwnedBytes(copying: $0) }
        }

        guard let provider = agent as? any AgentCapabilityProviding,
              let contract = actionContracts[envelope.capability],
              contract.input == envelope.representation else {
            throw AgentParticipantEndpointError.unsupportedCapability(
                envelope.capability
            )
        }
        let result = try await provider.invokeCapability(
            input,
            capability: envelope.capability
        )
        try Task.checkCancellation()
        return result.map { OwnedBytes(copying: $0) }
    }

    public func shutdown() async {
        if let shutdownTask {
            await shutdownTask.value
            return
        }
        guard case .running = state else {
            return
        }
        state = .shuttingDown
        let task = Task { [self] in
            await performShutdown()
        }
        shutdownTask = task
        await task.value
    }

    private func invocationFinished() {
        activeInvocationCount -= 1
        guard activeInvocationCount == 0,
              case .shuttingDown = state else {
            return
        }
        let waiter = drainWaiter
        drainWaiter = nil
        waiter?.resume()
    }

    private func performShutdown() async {
        if let shutdownHandler = agent as? any AgentShutdownHandling {
            await shutdownHandler.shutdown()
        }
        if activeInvocationCount > 0 {
            await withCheckedContinuation { continuation in
                drainWaiter = continuation
            }
        }
        state = .finished
        shutdownTask = nil
    }
}
