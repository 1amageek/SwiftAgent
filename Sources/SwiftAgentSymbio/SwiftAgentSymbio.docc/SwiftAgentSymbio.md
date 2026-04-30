# ``SwiftAgentSymbio``

Distributed runtime primitives for agent membership, routing, invocation, and
peer observations.

## Overview

SwiftAgentSymbio separates the philosophical concept of a community from the
concrete runtime object that executes local work. `Community` is the social
model described in `PHILOSOPHY.md`. ``SymbioRuntime`` is the implementation
surface that owns local agents, observes remote peers, and routes work through a
transport boundary.

`Community` is not required for every interaction. Direct one-to-one
conversation can remain direct, and even multi-party coordination can sometimes
be handled by a capable mediator without creating an explicit shared substrate.
In Symbio, community is a coordination affordance: a shared surface for claims,
observations, tasks, reviews, memory, and situated affordances when direct
communication is not enough.

Affordances complement capabilities. A capability is a relatively stable action
contract. An affordance is situated: what a member appears able to contribute
now under current constraints. A robot may have a camera capability but may not
currently see the target; a high-compute agent may analyze observations but
cannot act physically. Symbio keeps these differences visible so mixed
communities of robots, models, memory services, and people can complement one
another.

### Architecture

```text
Layer 4: Agent (Communicable)
    ↓
Layer 3: SymbioRuntime (members, local lifecycle, routing, observations)
    ↓
Layer 2: SymbioActorSystem + SymbioProtocol envelopes
    ↓
Layer 1: SymbioTransport
    ↓
Layer 0: PeerConnectivity, in-process, or custom transports
```

### Creating a Runtime

```swift
let actorSystem = SymbioActorSystem()
let runtime = SymbioRuntime(actorSystem: actorSystem)

let worker = try await runtime.spawn {
    WorkerAgent(runtime: runtime, actorSystem: actorSystem)
}

try await runtime.send(WorkSignal(task: "process"), to: worker.id, perception: "work")

for await change in await runtime.changes {
    switch change {
    case .joined(let participant): print("Joined: \(participant.id)")
    case .left(let participantID): print("Left: \(participantID)")
    default: break
    }
}
```

### Implementing a Communicable Agent

```swift
distributed actor WorkerAgent: Communicable, Terminatable {
    typealias ActorSystem = SymbioActorSystem

    let runtime: SymbioRuntime

    init(runtime: SymbioRuntime, actorSystem: SymbioActorSystem) {
        self.runtime = runtime
        self.actorSystem = actorSystem
    }

    nonisolated var perceptions: [any Perception] {
        [WorkPerception()]
    }

    distributed func receive(_ data: Data, perception: String) async throws -> Data? {
        let signal = try JSONDecoder().decode(WorkSignal.self, from: data)
        return nil
    }

    nonisolated func terminate() async {}
}
```

### Operation Capabilities

| Operation | Local | Remote |
|-----------|:-----:|:------:|
| spawn | yes | no |
| terminate | yes | no |
| send | yes | yes |
| invoke | yes | yes |

Remote behavior is provided through ``SymbioTransport``. The default
``LocalOnlySymbioTransport`` keeps runtime behavior deterministic for local-only
tests and applications.

Use the `SwiftAgentSymbioPeerConnectivity` product when a runtime should use a
`PeerConnectivitySession` as its remote transport. That adapter exchanges
``ParticipantDescriptor`` values over a descriptor stream and invocations over an
invocation stream.

## Topics

### Runtime

- ``SymbioRuntime``
- ``SymbioRuntimeChange``
- ``ParticipantID``
- ``ParticipantDescriptor``
- ``ParticipantView``
- ``Affordance``
- ``RoutePlan``

### Transport

- ``SymbioTransport``
- ``SymbioTransportEvent``
- ``SymbioInvocationEnvelope``
- ``SymbioInvocationReply``
- ``LocalOnlySymbioTransport``

### Agent Protocols

- ``Communicable``
- ``Terminatable``
- ``Replicable``

### Actor System

- ``SymbioActorSystem``
- ``Address``

### Tools

- ``ReplicateTool``
