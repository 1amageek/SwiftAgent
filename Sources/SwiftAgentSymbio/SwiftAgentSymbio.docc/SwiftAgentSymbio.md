# ``SwiftAgentSymbio``

Transport-independent participant ownership, trust, routing, and invocation runtime.

## Overview

`SwiftAgentSymbio` no longer owns a distributed-actor system or any concrete
networking framework. ``SymbioRuntime`` owns participant state and local
endpoints. ``SymbioLink`` is the narrow remote boundary, and adapters own wire
formats and network resources.

```text
Application or SwiftAgent adapter
    -> ParticipantEndpoint / ParticipantHandle
        -> SymbioRuntime
            -> ParticipantClaimVerifier
            -> InboundInvocationAuthorizer
            -> SymbioLink
                -> concrete network adapter
```

### Identity Boundaries

The following identities are intentionally distinct:

| Identity | Owner | Purpose |
|----------|-------|---------|
| ``ParticipantID`` | application/runtime | stable logical participant |
| ``ParticipantHandle`` | runtime | unforgeable local registration authority |
| ``TransportPeerID`` | link adapter | network connection peer |
| ``VerifiedParticipantBinding`` | claim verifier | verified participant-to-peer binding |

A network announcement produces a ``SymbioPeerClaim``. It never makes a remote
participant routable by itself. The default ``RejectingParticipantClaimVerifier``
fails closed. ``PinnedParticipantClaimVerifier`` requires the transport peer,
participant, authentication method, and authentication subject to match.

### Runtime Lifecycle

```swift
let identity = ParticipantDescriptor(
    id: "runtime.local",
    kind: .service
)
let runtime = try SymbioRuntime(identity: identity)
let endpoint = EchoEndpoint()
let handle = try await runtime.register(endpoint)

try await runtime.start()
let result = try await runtime.invoke(
    "echo",
    on: handle.participantID,
    representation: .typedPayload(schema: "echo"),
    with: payload,
    from: runtime.localHandle
)
try await runtime.stop()
```

The runtime control identity can originate work but cannot advertise executable
capabilities. Executable capabilities belong to registered
``ParticipantEndpoint`` instances. An endpoint must reject new work during
shutdown and drain work it already owns before `shutdown()` returns.

Runtime construction validates the control identity, execution budget, and
bounded work capacities. Invalid configuration fails with
``SymbioRuntimeError`` before any runtime state or transport ownership exists.

Local publication uses a complete desired-catalog snapshot. Registration and
withdrawal transitions are serialized so a suspended older snapshot cannot
overwrite a newer catalog.

Runtime shutdown is owned by one internal cleanup task. Caller cancellation
does not abandon link or endpoint cleanup, concurrent `stop()` calls await the
same result, and a typed cleanup failure can be retried.

Descriptor-declared affordances and runtime observations have independent
provenance inside the runtime. Replacing a descriptor replaces the declared
set exactly, while observations survive until their observation owner changes
them. ``ParticipantView`` exposes the deterministic merge: the declared owner
and contract remain authoritative, and observed availability and evidence can
only make the effective state more conservative.

Aggregate membership is an acyclic graph. Availability roll-up excludes
expired member observations and iterates to a fixed point, so nested aggregates
cannot depend on dictionary iteration order.

### Incoming Invocations

Incoming work passes every boundary in order:

```text
link event
    -> connected transport peer check
    -> verified participant binding check
    -> local endpoint and capability-contract check
    -> [ InboundInvocationAuthorizer
    -> binding and lifecycle revalidation
    -> endpoint invocation ] within one total execution budget
    -> typed reply
```

The default ``RejectingInboundInvocationAuthorizer`` denies incoming work.
``AllowingInboundInvocationAuthorizer`` is an explicit opt-in intended for
already trusted environments or tests. The smaller of the envelope execution
budget and the runtime limit covers authorization through endpoint completion;
authorization cannot hold an inbound slot outside that budget.

A verified participant binding is scoped to its transport connection. Peer
disconnect, withdrawal, link termination, runtime shutdown, or binding
replacement cancels inbound work derived from the stale binding. Authorizers
and endpoints must cooperate with task cancellation.

### Routing and Policy

``SymbioRuntime/planRoute(for:)`` produces a ``RoutePlan``. Before execution,
the runtime verifies sender authority, message expiry, availability expiry,
policy coverage, policy-decision expiry, the current capability contract, and
the current participant binding. If authorization or remote I/O suspends, the
sender and destination are checked again before dispatching or accepting a
result.

### Payload Ownership

Core payloads use `NetworkingCore.OwnedBytes`. Foundation `Data`, Codable wire
DTOs, and SwiftAgent-specific protocols belong in adapter targets. This keeps
the core independent and makes copies visible at serialization boundaries.

## Topics

### Runtime and Ownership

- ``SymbioRuntime``
- ``SymbioRuntimeChange``
- ``SymbioRuntimeError``
- ``ParticipantEndpoint``
- ``ParticipantHandle``

### Trust and Authorization

- ``ParticipantClaimVerifier``
- ``PinnedParticipantClaimVerifier``
- ``VerifiedParticipantBinding``
- ``InboundInvocationAuthorizer``
- ``PolicyAuthorizer``

### Link Boundary

- ``SymbioLink``
- ``SymbioLinkEvent``
- ``LocalOnlySymbioLink``
- ``TransportPeerID``
- ``SymbioInvocationEnvelope``
- ``SymbioInvocationReply``

### Participant Model

- ``ParticipantID``
- ``ParticipantDescriptor``
- ``ParticipantView``
- ``Affordance``
- ``CapabilityContract``
- ``Availability``
- ``Evidence``
- ``TrustView``

### Routing

- ``Message``
- ``MessageRepresentation``
- ``RoutePlan``
- ``RoutePlanStep``
