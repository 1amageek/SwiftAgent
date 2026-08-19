# SwiftAgentSymbio Design Record

## Status

This document describes the implemented architectural direction. Public API
details are documented in `Sources/SwiftAgentSymbio/*.swift`; the end-to-end
operational contract is in `Docs/SYMBIOSIS.md`.

The previous design coupled social routing to `DistributedActorSystem` and a
specific actor registry. That made transport identity, participant identity,
local execution ownership, and SwiftAgent adaptation one concern. The current
design separates those responsibilities and intentionally does not preserve the
old API.

## Invariants

| Invariant | Owner |
|---|---|
| A reachable transport peer is not an authenticated participant | `ParticipantClaimVerifier` |
| Core routing does not import SwiftAgent or PeerConnectivity | `SwiftAgentSymbio` target boundary |
| A local executable participant has exactly one endpoint owner | `SymbioRuntime` |
| Invalid identity or capacity configuration cannot enter runtime state | throwing `SymbioRuntime.init` |
| Endpoint shutdown rejects new work and drains owned invocations | `ParticipantEndpoint` |
| A remote invocation is authorized at the receiving runtime | `InboundInvocationAuthorizer` |
| An inbound execution budget covers authorization and endpoint execution together | `SymbioRuntime` |
| A sender, route, and authorization remain current at execution time | `SymbioRuntime` |
| A remote binding and its inbound work cannot outlive the transport connection | `SymbioRuntime` |
| Runtime and link cleanup outlive caller cancellation and have one owner | lifecycle owner task |
| Wire payload ownership is explicit | `OwnedBytes` and transport adapters |
| An aggregate view is not executable without an explicit endpoint | route planner |
| Declared contracts and observed state retain separate provenance | `ParticipantRecord` |

## Package Boundaries

```text
SwiftAgent application
    |
    v
SwiftAgentSymbioAgentAdapter
    |                 \
    v                  v
SwiftAgent       SwiftAgentSymbio ------> NetworkingCore
                         ^
                         |
SwiftAgentSymbioPeerConnectivity
             |
             v
    swift-peer-connectivity
```

| Package | Responsibility | Must not own |
|---|---|---|
| `SwiftAgentSymbio` | participant state, endpoint ownership, trust binding, policy, routing, lifecycle | SwiftAgent types, PeerConnectivity sessions, wire framing |
| `SwiftAgentSymbioAgentAdapter` | `Data`/`OwnedBytes` conversion and SwiftAgent actor adaptation | peer discovery, routing state, transport lifecycle |
| `SwiftAgentSymbioPeerConnectivity` | peer events, protocol streams, framing, bounded wire queues | social trust decisions, participant execution, SwiftAgent agents |

Dependencies point toward the core abstractions. The core never reaches back
into either adapter.

## Identity And Trust

```text
PeerConnectivity identity
    -> TransportPeerID + SymbioPeerAuthentication
    -> unverified SymbioPeerClaim
    -> ParticipantClaimVerifier
    -> VerifiedParticipantBinding
    -> routable remote ParticipantView
```

An announcement is self-description. It cannot directly create a route. The
runtime tracks peer connection generations and claim revisions across verifier
suspension points. A verification result is discarded when the peer disconnects,
the claim is withdrawn, or a newer claim supersedes it.

A verified binding is a connection-derived lease. Peer disconnection, participant
withdrawal, link termination, and runtime shutdown remove the lease and cancel
inbound work admitted through it. The endpoint and inbound authorizer must
cooperate with task cancellation so stale authority cannot continue executing.

The default verifier rejects all remote claims. Applications opt into a trust
model explicitly, such as exact participant/authentication pins or a custom
cryptographic verifier.

## Local Ownership

`SymbioRuntime.register(_:)` accepts a `ParticipantEndpoint` and returns a
`ParticipantHandle`. The runtime owns the endpoint until removal or runtime
shutdown. The opaque registration token in the handle prevents one caller from
removing another registration that reused the same participant identifier.

The runtime initializer validates its control identity and bounded capacities
before constructing state. Endpoint registration and verified remote bindings
pass through the same descriptor invariants, so no lifecycle phase can contain
an invalid participant descriptor.

```text
register endpoint
    -> validate descriptor
    -> install runtime ownership
    -> publish when link is running
    -> emit joined

remove handle / stop runtime
    -> reject new routes
    -> withdraw publication
    -> cancel and drain runtime-owned work
    -> endpoint.shutdown() drains endpoint-owned work
    -> release endpoint
```

Runtime stop runs in one runtime-owned task. Concurrent callers await the same
result, and cancelling a caller does not cancel link or endpoint cleanup. A
cleanup failure remains typed and retryable because the runtime does not claim
that resource ownership was released.

The runtime identity represents the control plane and therefore cannot
advertise executable capability contracts. Executable capabilities belong to
registered endpoints.

Publication and withdrawal both replace one complete desired local catalog.
Only one catalog transition may cross the link boundary at a time, preventing
an older suspended snapshot from overwriting a newer one.

## Routing And Invocation

Route planning produces an inspectable `RoutePlan`. Execution does not trust a
previous snapshot blindly: sender authority, availability, expiry, capability
compatibility, policy coverage, and participant binding are checked again after
suspension. A remote result is accepted only while the originating local sender
and destination binding are still current.

```text
message + participant view
    -> representation and affordance selection
    -> policy requirements
    -> authorization decision
    -> fresh route recomputation
    -> local endpoint or verified remote binding
    -> invocation
```

Local invocation calls the runtime-owned endpoint. Remote invocation sends a
`SymbioInvocationEnvelope` through `SymbioLink` to a verified transport peer.
The receiving runtime authenticates the peer-derived principal, authorizes the
capability, invokes its local endpoint, and returns a reply through the opaque
`SymbioReplyContext` supplied by the link.

Timeout helpers use structured concurrency. A timeout cancels the operation and
does not let an unowned task outlive the call. Endpoint and link implementations
must cooperate with cancellation and drain their owned operations at shutdown.

The PeerConnectivity adapter receives its monotonic `AsyncTimer` as a dependency.
It classifies completion from the observed absolute completion instant, treats
completion at the deadline as timeout, and surfaces timer backend failure instead
of silently disabling the deadline. Timer failure enters the same owned cleanup
and drain path as timeout.

The adapter binds inbound and outbound channels to the authenticated transport
peer value and its current connection generation. Identity replacement under a
reused peer ID is represented as an ordered disconnect/connect transition.
Generation checks reject late completions from a retired connection, while reply
correlation IDs prevent a response from crossing invocation ownership boundaries.

## Aggregate Participants

An `AggregateParticipantDescriptor` is a local observation and availability
roll-up over members. It is intentionally not routable by itself. Executing an
aggregate requires a concrete endpoint that owns member selection, quorum,
failure, and cancellation semantics. Until such an endpoint is registered,
direct aggregate invocation is rejected rather than returning a false route.

The membership graph must be acyclic. Nested availability is recalculated to a
fixed point, and expired member availability is not counted. This makes roll-up
independent of registration and dictionary iteration order.

Descriptor-declared affordances and runtime-observed affordances are stored as
separate provenance sets. Descriptor replacement replaces only declarations;
it neither preserves stale declarations nor erases observations. The exported
participant view performs a deterministic merge in which the declared owner
and contract are authoritative and observed state can only make availability
more conservative.

## Transport Contract

`SymbioLink` is the only transport abstraction visible to the core. It owns:

- start and shutdown;
- participant publication and withdrawal;
- exactly one inbound event receiver;
- remote invocation and reply correlation;
- transport-specific peer identity.

The PeerConnectivity adapter uses versioned invocation and announcement
protocol identifiers. It bounds event, reply, and wire buffers. It disables
implicit identity trust: authentication evidence is derived from the connected
peer object, never from announcement payload fields.

New outbound work has a separate concurrency limit from admitted inbound reply
work. A reply context has already consumed a bounded pending-reply slot, so its
completion is allowed to drain even when the new-operation limit is full.
Shutdown starts owned-channel close and parent-session shutdown concurrently
before waiting for I/O; this avoids parent/child cleanup ordering deadlocks.
Session startup is also bounded. Timeout or caller cancellation enters the same
session-owner cleanup path, and the backend must make a suspended start return
when shutdown begins.

## Failure Contract

| Failure | Contract |
|---|---|
| Clean receiver completion | `receive()` returns `nil` |
| Link or stream failure | typed error propagates and runtime transitions to failure/stop |
| Unverified or stale claim | no binding and no route |
| Missing/expired authorization | invocation rejected |
| Response correlation mismatch | channel is released and the mismatched reply is rejected |
| Queue capacity exceeded | explicit overload failure; no silent drop |
| Shutdown cleanup failure | aggregated typed cleanup error |
| Peer or link lifetime ends | derived bindings removed and admitted inbound work cancelled |
| Stop caller is cancelled | owner cleanup continues; other callers await the same result |

## Extension Rules

New transports implement `SymbioLink` in a separate adapter target. New agent
frameworks implement `ParticipantEndpoint` in their own adapter. Neither change
requires adding framework-specific imports or conditional branches to
`SwiftAgentSymbio`.

New aggregate execution behavior must be modeled as an endpoint with explicit
selection, authorization, cancellation, and partial-failure contracts. It must
not be added as an implicit branch in the view roll-up logic.

## Verification Matrix

| Boundary | Success behavior | Failure behavior | Concurrency behavior |
|---|---|---|---|
| endpoint registration | one owner and one handle | duplicate or invalid descriptor rejected | publication suspension is revalidated |
| claim verification | current connected claim becomes a binding | stale/disconnected claim discarded | generation and revision guarded |
| route execution | current authorized endpoint invoked | stale, blocked, expired, or unsupported route rejected | state rechecked after awaits |
| link invocation | correlated reply returned | timeout, disconnect, mismatch, overflow surfaced | channel/session cleanup starts before active I/O drain |
| connection-derived binding | current peer can route and authorize inbound work | disconnect/withdraw/link end revokes the binding | matching inbound tasks are cancelled |
| runtime shutdown | link and endpoints release all owned work | cleanup failure remains retryable | one owner task is shared by callers and ignores caller cancellation |
| adapter conversion | conversion occurs once at boundary | malformed representation rejected | owner retained across async call |

Compilation and runtime verification requirements remain target-specific. A
successful declaration scan alone is not evidence that these behaviors work.
