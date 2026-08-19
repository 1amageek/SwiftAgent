# ``SwiftAgentSymbioAgentAdapter``

The explicit boundary between SwiftAgent agents and the transport-independent Symbio core.

## Overview

This target owns every dependency on `SwiftAgent`, `Foundation.Data`,
`Perception`, and model-facing tools. `SwiftAgentSymbio` remains independent.

``AgentParticipantEndpoint`` snapshots an agent's declared perceptions and
action contracts, rejects duplicate identifiers, validates every invocation
against the advertised representation, and reserves the
`agent.perception.` capability namespace for perception dispatch. During
shutdown it asks an ``AgentShutdownHandling`` agent to reject and release its
owned work before waiting for active endpoint invocations to drain. `Data` and
`OwnedBytes` are copied only at this adapter boundary.

```text
CommunicableAgent
    -> AgentParticipantEndpoint
        -> ParticipantEndpoint
            -> SymbioRuntime
```

```text
AgentShutdownHandling.shutdown()
    -> active invocation drain
        -> endpoint finished
```

Use ``SymbioRuntime/send(_:to:perception:from:authorizer:timeout:)`` for encoded
perception delivery. Use
``SymbioRuntime/invokeAgentCapability(_:on:representation:with:from:authorizer:timeout:)``
when the caller already knows the action contract's representation.

## Topics

### Agent Boundary

- ``CommunicableAgent``
- ``AgentCapabilityProviding``
- ``AgentShutdownHandling``
- ``AgentParticipantEndpoint``
- ``AgentParticipantEndpointError``

### Tools

- ``Replicable``
- ``ReplicateTool``
