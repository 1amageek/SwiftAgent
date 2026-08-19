# ``SwiftAgentSymbioPeerConnectivity``

A PeerConnectivity adapter for the transport-independent `SwiftAgentSymbio` link boundary.

## Overview

``PeerConnectivitySymbioLink`` owns one `PeerConnectivitySession`, subscribes
before starting it, and translates network events and stream channels into
``SymbioLinkEvent`` values. The adapter never treats a transport peer identifier
as a participant identifier.

```text
PeerConnectivityPeer
    -> TransportPeerID
    -> unverified SymbioPeerClaim
    -> SymbioRuntime claim verifier
    -> VerifiedParticipantBinding
```

### Mapping

| PeerConnectivity | Symbio |
|------------------|--------|
| session lifecycle | ``SymbioLink`` lifecycle |
| backend peer ID | ``TransportPeerID`` |
| backend identity | ``SymbioPeerAuthentication`` input |
| announcement stream | unverified participant publish/withdraw events |
| invocation stream | invocation envelope and exactly one reply |

The link requires `.streamMultiplexing`. It has one receive owner, bounded event
and pending-reply storage, a bound for new outbound operations, bounded wire
messages, explicit timeouts, and retryable terminal cleanup. Already admitted
reply work drains independently of the new-operation limit. Shutdown starts
owned-channel close and parent-session shutdown concurrently, then waits for
channel tasks and active I/O to drain. The adapter owns that cleanup task:
caller cancellation cannot abandon it, and concurrent shutdown callers await
the same terminal result.

Deadlines use the injected `NetworkingTime.AsyncTimer` and compare the actual
operation completion instant with the absolute deadline. Completion at the
deadline is a timeout. A timer failure is surfaced as
``PeerConnectivitySymbioError/deadlineFailed(_:)`` and owns the same I/O cleanup
and drain path as a timeout.

Every channel is bound to the current transport-peer identity and connection
generation. Replacing an identity under the same transport ID emits an ordered
disconnect/connect transition; a late channel completion or stale disconnect
from the prior generation cannot be applied to the replacement. Invocation
replies must preserve their request correlation ID before the channel is released.

Each stream direction carries exactly one length-prefixed frame. A frame uses a
four-byte unsigned big-endian payload length followed by one JSON payload. The
adapter accumulates arbitrary `PeerConnectivityChannel.read()` chunks until the
declared payload is complete; transport read boundaries are never interpreted
as message boundaries. The declared length is checked against the configured
wire limit before payload storage is reserved, and bytes beyond the single
declared payload are rejected.

The supplied backend must unblock outstanding `openChannel`, channel `read`,
channel `write`, and session `start` calls when a channel closes or the session
shuts down. Startup uses the configured operation deadline; timeout or caller
cancellation initiates the session owner's shutdown and drains startup before
returning. The
PeerConnectivity protocol does not encode that guarantee in its type system;
the adapter treats a non-cooperative backend as a contract violation. When a
deadline expires before `openChannel` returns, the adapter terminates the
parent session because the upstream API exposes no per-open cancellation
handle.

### Wiring a Runtime

```swift
let session: PeerConnectivitySession = makePeerConnectivitySession()
let link = PeerConnectivitySymbioLink(session: session)
let verifier = PinnedParticipantClaimVerifier(pinsByPeerID: [
    "transport.remote": [
        .init(
            participantID: "worker.remote",
            authenticationMethod: "peer-connectivity:authenticated-backend",
            authenticationSubject: "remote-key"
        )
    ]
])
let runtime = try SymbioRuntime(
    identity: ParticipantDescriptor(id: "runtime.local", kind: .service),
    link: link,
    claimVerifier: verifier,
    inboundAuthorizer: RejectingInboundInvocationAuthorizer()
)

try await runtime.start()
```

Applications should derive pins from an authenticated provisioning or trust
flow. Announcement payloads cannot choose their own authentication identity;
the adapter derives it from `PeerConnectivityPeer.identity`.

### Protocol IDs

- ``PeerConnectivitySymbioLink/defaultInvocationProtocolID`` — `/swiftagent/symbio/invoke/2.0.0`
- ``PeerConnectivitySymbioLink/defaultAnnouncementProtocolID`` — `/swiftagent/symbio/announce/2.0.0`

Changing a protocol ID is an explicit wire compatibility decision.

## Topics

### Link

- ``PeerConnectivitySymbioLink``
- ``PeerConnectivitySymbioError``
