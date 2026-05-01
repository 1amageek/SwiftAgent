# ``SwiftAgentSymbioPeerConnectivity``

PeerConnectivity-backed transport adapter for `SwiftAgentSymbio`.

## Overview

This module exposes a single primary type, ``PeerConnectivitySymbioTransport``,
which adapts a `PeerConnectivitySession` to the
`SymbioTransport` boundary expected by `SymbioRuntime`. With this adapter,
a SwiftAgent runtime can discover peers and exchange invocations across local
networks (Wi-Fi, Bluetooth, AWDL) without depending on networking framework
types in the core.

### How It Maps

| PeerConnectivity concept | Symbio concept |
|--------------------------|----------------|
| `PeerConnectivitySession` | underlying transport session |
| descriptor stream | exchanges `ParticipantDescriptor` updates |
| invocation stream | exchanges `SymbioInvocationEnvelope` / `SymbioInvocationReply` |
| peer events (`joined`, `left`, …) | bridged to `SymbioTransportEvent` |

The adapter requires the underlying session to support stream multiplexing
(`session.require(.streamMultiplexing)` is checked at start time).

### Wiring a Runtime

```swift
import SwiftAgent
import SwiftAgentSymbio
import SwiftAgentSymbioPeerConnectivity
import PeerConnectivity

let session: PeerConnectivitySession = …  // application-specific configuration

let transport = PeerConnectivitySymbioTransport(
    session: session,
    localDescriptor: ParticipantDescriptor(id: myID, kind: .agent)
)

let runtime = SymbioRuntime(
    actorSystem: SymbioActorSystem(),
    transport: transport
)

try await runtime.start()
```

### Protocol IDs

The default invocation and descriptor stream IDs are exposed as static members
so consumers can negotiate compatibility:

- ``PeerConnectivitySymbioTransport/defaultInvocationProtocolID`` — `/swiftagent/symbio/invoke/1.0.0`
- ``PeerConnectivitySymbioTransport/defaultDescriptorProtocolID`` — `/swiftagent/symbio/descriptor/1.0.0`

Override the protocol IDs at init time when running mixed versions in parallel.

## Topics

### Transport

- ``PeerConnectivitySymbioTransport``

### Metadata

- ``PeerConnectivitySymbioMetadata``
