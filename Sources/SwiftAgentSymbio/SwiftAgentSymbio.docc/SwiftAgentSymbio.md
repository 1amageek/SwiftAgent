# ``SwiftAgentSymbio``

Distributed runtime primitives for agent membership, situated affordances, routing, invocation, and peer observation.

## Overview

SwiftAgentSymbio separates the philosophical concept of a *community* (described in `PHILOSOPHY.md`) from the concrete runtime that executes local work. ``SymbioRuntime`` is the implementation surface that owns local agents, observes remote peers, and routes work through a transport boundary.

`Community` is not required for every interaction. Direct one-to-one conversation can remain direct, and even multi-party coordination can sometimes be handled by a capable mediator without creating an explicit shared substrate. In Symbio, community is a coordination *affordance*: a shared surface for claims, observations, tasks, reviews, memory, and situated affordances when direct communication is not enough.

### Capabilities vs Affordances

A **capability** is a relatively stable action contract — what an agent is *able* to do. An **affordance** is situated: what a member appears able to contribute *now* under current constraints. A robot may have a camera capability but may not currently see the target; a high-compute agent may analyze observations but cannot act physically. Symbio keeps these differences visible so mixed communities of robots, models, memory services, and people can complement one another.

### Architecture

```text
Layer 4: Agent (Communicable)
    ↓
Layer 3: SymbioRuntime (members, lifecycle, routing, observations, affordances)
    ↓
Layer 2: SymbioActorSystem + SymbioProtocol envelopes
    ↓
Layer 1: SymbioTransport
    ↓
Layer 0: PeerConnectivity, in-process, or custom transports
```

### Operation Capabilities

| Operation | Local | Remote |
|-----------|:-----:|:------:|
| `spawn` | yes | no |
| `terminate` | yes | no |
| `send` | yes | yes |
| `invoke` | yes | yes |

Remote behavior is provided through ``SymbioTransport``. The default ``LocalOnlySymbioTransport`` keeps runtime behavior deterministic for local-only tests and applications. Use the `SwiftAgentSymbioPeerConnectivity` product when a runtime should use a `PeerConnectivitySession` as its remote transport.

### Creating a Runtime

```swift
let actorSystem = SymbioActorSystem()
let runtime = SymbioRuntime(actorSystem: actorSystem)

try await runtime.start()
defer { Task { try? await runtime.stop() } }

let worker = try await runtime.spawn {
    WorkerAgent(runtime: runtime, actorSystem: actorSystem)
}

try await runtime.send(
    WorkSignal(task: "process"),
    to: worker.id,
    perception: "work"
)

for await change in await runtime.changes {
    switch change {
    case .joined(let participant): print("Joined: \(participant.id)")
    case .left(let id):           print("Left: \(id)")
    default: break
    }
}
```

`runtime.start()` wires the transport's invocation handler and begins descriptor monitoring. `runtime.stop()` terminates local agents and finishes the change stream.

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
        // …handle signal…
        return nil
    }

    nonisolated func terminate() async {}
}
```

### Observing Affordances and Evidence

The runtime tracks per-participant ``ParticipantView`` state including affordances, evidence, claims, trust views, and availability. Use the `observe(...)` overloads to feed in new observations:

```swift
runtime.observe(myEvidence)
runtime.observe(myAffordance)
runtime.observe(myTrustView)
runtime.updateAvailability(of: peerID, to: .ready)
runtime.block(peerID, reason: "rate-limited")
```

### Planning a Route

``SymbioRuntime/planRoute(for:)`` produces a ``RoutePlan`` containing the candidate ``RoutePlanStep`` sequence, policy decisions, and evidence references. Plans are advisory: callers decide whether to dispatch the message based on the embedded policy outcome.

```swift
let plan = runtime.planRoute(for: message)
guard plan.policyDecision.state == .approved else {
    throw RoutingDenied(reasons: plan.policyDecision.reasons)
}
// Dispatch the steps in `plan.steps` through `runtime.send` / `invoke`
// according to your application's delivery policy.
```

## Topics

### Runtime

- ``SymbioRuntime``
- ``SymbioRuntimeChange``
- ``SymbioActorSystem``

### Participants

- ``ParticipantID``
- ``ParticipantDescriptor``
- ``AggregateParticipantDescriptor``
- ``ParticipantView``

### Affordances and Capabilities

- ``Affordance``
- ``CapabilityContract``
- ``DeliveryOption``
- ``Evidence``
- ``TrustView``

### Routing and Messaging

- ``Message``
- ``MessageRepresentation``
- ``RoutePlan``
- ``RoutePlanStep``

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

### Addressing

- ``Address``

### Tools

- ``ReplicateTool``
