# ``SwiftAgentSymbio``

Distributed actor system for multi-agent communication and discovery.

## Overview

SwiftAgentSymbio enables agents to communicate and discover each other across processes
and networks using Swift Distributed Actors.

### Architecture

```
Layer 4: Agent (Communicable = CommunityAgent + SignalReceivable)
    ↓
Layer 3: Community (member management, spawn/terminate/send)
    ↓
Layer 2: SymbioActorSystem + PeerConnector (Distributed Actor infrastructure)
    ↓
Layer 1: swift-discovery (transport abstraction)
    ↓
Layer 0: Transport (mDNS/TCP, BLE, HTTP/WebSocket)
```

### Creating a Community

```swift
let actorSystem = SymbioActorSystem()
let community = Community(actorSystem: actorSystem)

// Spawn a local agent
let worker = try await community.spawn {
    WorkerAgent(community: community, actorSystem: actorSystem)
}

// Send signals
try await community.send(WorkSignal(task: "process"), to: worker, perception: "work")

// Monitor changes
for await change in await community.changes {
    switch change {
    case .joined(let member): print("Joined: \(member.id)")
    case .left(let member): print("Left: \(member.id)")
    default: break
    }
}
```

### Implementing a Communicable Agent

```swift
distributed actor WorkerAgent: Communicable, Terminatable {
    typealias ActorSystem = SymbioActorSystem

    let community: Community

    nonisolated var perceptions: [any Perception] {
        [WorkPerception()]
    }

    distributed func receive(_ data: Data, perception: String) async throws -> Data? {
        let signal = try JSONDecoder().decode(WorkSignal.self, from: data)
        // Process signal...
        return nil
    }

    nonisolated func terminate() async {
        // Cleanup...
    }
}
```

### Operation Capabilities

| Operation | Local | Remote |
|-----------|:-----:|:------:|
| spawn | ✅ | ❌ |
| terminate | ✅ | ❌ |
| send | ✅ | ✅ |
| invoke (capability) | ❌ | ✅ |

### Dynamic Agent Replication

LLMs can spawn sub-agents dynamically using ``ReplicateTool``:

```swift
let session = LanguageModelSession(tools: [ReplicateTool(agent: workerAgent)]) {
    Instructions("Spawn helper agents when tasks are complex.")
}
```

## Topics

### Community Management

- ``Community``
- ``CommunityChange``
- ``Member``

### Agent Protocols

- ``Communicable``
- ``Terminatable``
- ``Replicable``

### Actor System

- ``SymbioActorSystem``
- ``Address``
- ``PeerConnector``

### Tools

- ``ReplicateTool``
