# SwiftAgentSymbio Zero-Base Design

This document defines the new Symbio design from first principles.

## Purpose

SwiftAgentSymbio exists to let asymmetric participants cooperate:

| Participant | What it may contribute | What it may lack |
|---|---|---|
| Physical robot | embodied sensing, physical action, local constraints | large context, heavy reasoning |
| High-compute model | planning, analysis, language, mediation | direct physical access |
| Memory service | retrieval, continuity, provenance | present-time observation |
| Human | intent, values, accountability | constant monitoring |
| Low-level controller | deterministic bounded control | natural-language understanding |

The design must support cooperation without assuming that all participants are
LLMs, understand natural language, expose stable service catalogs, or share one
global truth.

```text
participant -> observation / message / action / claim
           -> local view
           -> route, mediate, ask, invoke, or externalize
```

## Non-Goals

Symbio should not become:

| Non-goal | Reason |
|---|---|
| A global registry | each runtime has a subjective local view |
| A service discovery table | cooperation often starts without knowing what the other can do |
| A command hierarchy | remote participants are autonomous |
| A natural-language-only bus | many useful participants cannot parse language |
| A single trust score | trust is domain-specific, temporal, and evidence-based |
| A mandatory community object | direct or mediated communication may be enough |

## Core Concepts

| Concept | Meaning |
|---|---|
| `Participant` | An autonomous entity the runtime can observe or address |
| `Message` | A directed or open input carried in a specific representation |
| `Representation` | The form of a message: language, typed payload, sensor frame, command, resource reference |
| `Affordance` | A situated possibility: what a participant appears able to contribute now |
| `CapabilityContract` | A stable, explicit action contract that can be invoked under policy |
| `Claim` | A provenance-bearing statement, not global truth |
| `Evidence` | A local observation about behavior, outcome, safety, accuracy, or reliability |
| `TrustView` | A derived domain-specific view from evidence |
| `CoordinationSurface` | Optional externalized shared work surface, like an issue or field log |

```text
capability = stable contract
affordance = situated possibility
trust = derived from evidence, never a scalar authority
community = optional coordination affordance
```

## Layering

```text
Layer 5: Optional CoordinationSurface
  posts, tasks, claims, reviews, assignments, shared logs

Layer 4: Coordinator
  route, mediate, decide whether to externalize coordination

Layer 3: Local Social View
  participants, affordances, claims, evidence, trust views, constraints

Layer 2: Symbio Protocol
  descriptors, messages, invocation envelopes, replies, observations

Layer 1: Transport Adapter
  peer discovery, streams, resources, local process transport

Layer 0: Concrete transport
  PeerConnectivity, in-process, file/log, custom robot link
```

Transport reachability is not social meaning. A reachable peer may be unsafe,
irrelevant, unable to interpret the message, or useful only through a mediator.

## Participant

`Participant` is a compact identity and descriptor snapshot for an autonomous
entity the runtime can observe or address.

```swift
public struct ParticipantID: Sendable, Codable, Hashable {
    public let rawValue: String
}

public enum ParticipantKind: String, Sendable, Codable, Hashable {
    case agent
    case robot
    case human
    case memory
    case controller
    case tool
    case aggregate
    case unknown
}

public struct ParticipantDescriptor: Sendable, Codable, Hashable {
    public let id: ParticipantID
    public let displayName: String?
    public let kind: ParticipantKind
    public let representations: Set<MessageRepresentation>
    public let capabilityContracts: Set<CapabilityContract>
    public let selfClaims: [Claim]
    public let metadata: [String: String]
}
```

Descriptor data is self-description. It becomes input to the local view; it does
not become authority.

## Aggregate Participants

Groups, swarms, squads, rooms, and teams are first-class participants. An
aggregate participant is not just a tag over many individual participants. It
has composition, roll-up policy, degradation behavior, and route expansion.

```text
individual participants
  -> aggregate composition
  -> aggregate affordance
  -> route plan
  -> member assignments or aggregate controller invocation
```

```swift
public enum AggregateKind: String, Sendable, Codable, Hashable {
    case swarm
    case squad
    case team
    case room
    case deviceGroup
    case formation
}

public struct AggregateMember: Sendable, Codable, Hashable {
    public let participantID: ParticipantID
    public let role: String?
    public let weight: Double
    public let isRequired: Bool
    public let domains: Set<String>
}

public enum RollupRule: Sendable, Codable, Hashable {
    case any
    case all
    case minimumCount(Int)
    case quorum(Double)
    case weightedThreshold(Double)
    case roleCoverage(Set<String>)
}

public enum DegradationMode: String, Sendable, Codable, Hashable {
    case unavailable
    case degraded
    case split
    case fallback
}

public struct RollupPolicy: Sendable, Codable, Hashable {
    public let availabilityRule: RollupRule
    public let affordanceRule: RollupRule
    public let evidenceRule: RollupRule
    public let degradationMode: DegradationMode
    public let maxEvidenceAge: Duration?
    public let minConfidence: Double
}

public struct AggregateParticipantDescriptor: Sendable, Codable, Hashable {
    public let descriptor: ParticipantDescriptor
    public let aggregateKind: AggregateKind
    public let members: [AggregateMember]
    public let rollupPolicy: RollupPolicy
}
```

Aggregate membership is local view state. It may be declared by a controller,
inferred from discovery, created by a route planner, or loaded from a field
configuration. It is still not global truth.

### Aggregate Affordance

Aggregate affordances must be traceable to member affordances and evidence.

```swift
public struct AggregateAffordanceSource: Sendable, Codable, Hashable {
    public let participantID: ParticipantID
    public let affordanceID: String
    public let role: String?
    public let contribution: Double
}

public struct AggregateAffordance: Identifiable, Sendable, Codable, Hashable {
    public let id: String
    public let aggregateID: ParticipantID
    public let kind: String
    public let target: String?
    public let state: AffordanceState
    public let confidence: Double
    public let sources: [AggregateAffordanceSource]
    public let constraints: Set<String>
    public let observedAt: Date
    public let expiresAt: Date?
}
```

Examples:

| Aggregate | Roll-up meaning |
|---|---|
| drone swarm `survey.area(zone-7)` | enough drones can cover the zone before expiry |
| robot soccer `formation.support` | required field roles are currently covered |
| room `lighting.control` | controller and at least one target light are available |
| sensor mesh `temperature.observe(room)` | enough sensors agree within freshness bounds |

### Aggregate Routing

A route can target an aggregate, but execution must be explicit about how that
aggregate is realized.

```swift
public enum AggregateExecutionMode: String, Sendable, Codable, Hashable {
    case controller
    case memberAssignments
    case broadcast
    case quorum
}

public struct AggregateRouteExpansion: Sendable, Codable, Hashable {
    public let aggregateID: ParticipantID
    public let mode: AggregateExecutionMode
    public let assignments: [ParticipantID: String]
    public let requiredQuorum: Double?
    public let fallbackParticipantIDs: [ParticipantID]
}
```

| Mode | Use |
|---|---|
| `controller` | swarm controller, Matter controller, team tactical controller |
| `memberAssignments` | soccer roles, drone sector assignments |
| `broadcast` | low-risk open update to all members |
| `quorum` | sensing, voting, consensus, multi-sensor confirmation |

Aggregate failure should degrade the aggregate affordance rather than silently
disappear. If a required member fails, the aggregate route either degrades,
splits into smaller aggregates, uses fallback members, or rejects the plan.

## Message Representation

Natural language is supported, but it is only one representation.

```swift
public enum MessageRepresentationKind: String, Sendable, Codable, Hashable {
    case naturalLanguage
    case typedPayload
    case sensorFrame
    case actuatorCommand
    case resourceReference
    case binaryFrame
}

public struct MessageRepresentation: Sendable, Codable, Hashable {
    public let kind: MessageRepresentationKind
    public let schema: String?
    public let language: String?
    public let contentType: String?
}
```

| Representation | Example | Direct recipient |
|---|---|---|
| natural language | Japanese question text | LLM, human |
| typed payload | `VisibilityQuery` | robot perception service |
| sensor frame | image or depth frame | vision model, logger |
| actuator command | bounded motor bias | physical controller |
| resource reference | stored artifact ID | memory or analysis agent |
| binary frame | custom bus packet | low-level endpoint |

Representation compatibility is a hard direct-delivery concern. Semantic topic
matching is not.

## Message

`Message` is the general input unit for direct, mediated, or open
communication.

```swift
public enum MessageAddressing: Sendable, Codable, Hashable {
    case direct(ParticipantID)
    case open
    case group(Set<ParticipantID>)
}

public struct Message: Identifiable, Sendable, Codable, Hashable {
    public let id: String
    public let senderID: ParticipantID
    public let addressing: MessageAddressing
    public let representation: MessageRepresentation
    public let topic: String?
    public let payload: Data
    public let correlationID: String?
    public let createdAt: Date
}
```

`topic` is a hint for routing and interpretation. It must not be the only
contract.

## Affordance

An affordance is local, situated, and time-sensitive. It is not a promise.

```swift
public enum AffordanceState: String, Sendable, Codable, Hashable {
    case available
    case unavailable
    case uncertain
}

public struct Affordance: Identifiable, Sendable, Codable, Hashable {
    public let id: String
    public let subjectID: ParticipantID
    public let kind: String
    public let target: String?
    public let state: AffordanceState
    public let confidence: Double
    public let supportedRepresentations: Set<MessageRepresentation>
    public let deliveryOptions: Set<DeliveryOption>
    public let constraints: Set<String>
    public let evidenceIDs: Set<String>
    public let issuerID: ParticipantID
    public let observedAt: Date
    public let expiresAt: Date?
}
```

| Affordance | Meaning |
|---|---|
| `visual.visibility(target: tower-1)` | subject may currently see the tower |
| `physical.reachability(target: door-2)` | subject may be able to approach the door |
| `analysis.image(target: image-42)` | subject may analyze the image |
| `translation.intent(target: robot-7)` | subject may translate intent for a robot |
| `communication.response` | subject may respond through a representation |

Affordances are the main routing primitive for situated cooperation.

## Delivery Affordance

Delivery is also an affordance. The runtime should not hard-code that a given
affordance always travels over UDP, a stream, a log, or request/response. It
should describe which delivery semantics appear suitable and available for the
current message, participant, and task.

```swift
public enum DeliverySemantics: String, Sendable, Codable, Hashable {
    case bestEffortLatest
    case reliableEvent
    case durableRecord
    case requestResponse
}

public struct DeliveryOption: Sendable, Codable, Hashable {
    public let semantics: DeliverySemantics
    public let transportHint: String?
    public let maxLatency: Duration?
    public let expiresAfter: Duration?
    public let requiresAck: Bool
    public let ordering: FreshnessOrdering?
}
```

| Delivery semantics | Meaning | Typical use |
|---|---|---|
| `bestEffortLatest` | newest value matters; loss is acceptable | ball position, drone telemetry, swarm heartbeat |
| `reliableEvent` | event should arrive, but long-term audit is not required | device state change, degraded sensor event |
| `durableRecord` | event must be replayable or auditable | safety violation, mission result, command acceptance |
| `requestResponse` | caller needs a reply or explicit failure | capability invocation, Matter command, route approval |

Transport names are hints, not semantics. UDP multicast, QUIC datagrams,
Bluetooth advertisements, local shared memory, or gossip can all provide
`bestEffortLatest` in different environments. Streams, queues, append-only logs,
or resource stores can provide the more reliable semantics.

```text
delivery need
  -> available delivery affordances
  -> route plan chooses a delivery option
  -> transport adapter realizes it
```

The route planner should choose delivery by task semantics:

| Data | Preferred delivery |
|---|---|
| high-rate position or field state | `bestEffortLatest` |
| short-lived tactical affordance | `bestEffortLatest` with expiry and sequence |
| participant health transition | `reliableEvent` |
| action command | `requestResponse` |
| audit, evidence, or safety event | `durableRecord` |

This lets a swarm use UDP-like dissemination for fresh affordance updates while
still using reliable or durable paths for action, policy, and evidence.

Freshness ordering is required for best-effort latest delivery. Receivers must
be able to reject older updates.

```swift
public enum FreshnessOrderingKind: String, Sendable, Codable, Hashable {
    case sequence
    case frame
    case monotonicTime
}

public struct FreshnessOrdering: Sendable, Codable, Hashable {
    public let kind: FreshnessOrderingKind
    public let sourceID: ParticipantID
    public let streamID: String
}
```

## Capability Contract

Capabilities remain, but only for explicit action contracts.

```swift
public struct CapabilityContract: Identifiable, Sendable, Codable, Hashable {
    public let id: String
    public let representation: MessageRepresentation
    public let sideEffectLevel: SideEffectLevel
    public let requiredPolicies: Set<String>
}

public enum SideEffectLevel: String, Sendable, Codable, Hashable {
    case none
    case informational
    case resourceConsuming
    case worldAffecting
    case safetyCritical
}
```

`invoke` should require a capability contract. `send` should not.

## Claims And Evidence

Distributed statements are claims. Local observations are evidence.

```swift
public struct Claim: Identifiable, Sendable, Codable, Hashable {
    public let id: String
    public let subject: String
    public let predicate: String
    public let object: String
    public let issuerID: ParticipantID
    public let confidence: Double
    public let issuedAt: Date
    public let expiresAt: Date?
}

public enum EvidenceKind: String, Sendable, Codable, Hashable {
    case messageDelivered
    case messageFailed
    case replyReceived
    case taskSucceeded
    case taskFailed
    case claimVerified
    case claimContradicted
    case safetyViolation
    case refusal
    case timeout
}

public struct Evidence: Identifiable, Sendable, Codable, Hashable {
    public let id: String
    public let subjectID: ParticipantID
    public let domain: String
    public let kind: EvidenceKind
    public let relatedClaimID: String?
    public let relatedMessageID: String?
    public let confidence: Double
    public let observedAt: Date
    public let issuerID: ParticipantID
}
```

Claims can come from remote peers. Evidence is recorded by the local runtime or
trusted local observers.

## Trust

Trust is not a scalar authority.

Trust is a derived, domain-specific view over evidence. It can support ranking,
but it must not replace policy.

```swift
public struct TrustView: Sendable, Codable, Hashable {
    public let subjectID: ParticipantID
    public let domain: String
    public let reliability: Double
    public let accuracy: Double?
    public let safety: Double?
    public let freshness: Double
    public let evidenceCount: Int
    public let generatedAt: Date
}
```

| Decision | May use TrustView | Must use policy |
|---|:---:|:---:|
| route ranking | yes | yes |
| private context disclosure | yes | yes |
| remote claim acceptance | yes | yes |
| physical action | yes | yes |
| safety-critical control | only as evidence | yes |

Trust is never self-declared. It is inferred from local evidence and scoped by
domain.

## Local Social View

The runtime owns a subjective view.

```swift
public struct ParticipantView: Identifiable, Sendable, Codable, Hashable {
    public var id: ParticipantID { descriptor.id }
    public let descriptor: ParticipantDescriptor
    public let availability: Availability
    public let affordances: [Affordance]
    public let claims: [Claim]
    public let evidence: [Evidence]
    public let trustViews: [TrustView]
    public let constraints: Set<String>
    public let isBlocked: Bool
}
```

The local social view is subjective. It is not a global registry and should not
be treated as a shared source of truth.

Availability is reachability and participation state. It is not the same as an
affordance. A participant can be reachable but unable to perform a task, or
unreachable while its last known affordance is still relevant for audit.

```swift
public enum AvailabilityState: String, Sendable, Codable, Hashable {
    case available
    case degraded
    case unavailable
    case unknown
}

public struct Availability: Sendable, Codable, Hashable {
    public let state: AvailabilityState
    public let observedAt: Date
    public let expiresAt: Date?
    public let reasons: Set<String>
}
```

## Communication Semantics

### Direct Send

Direct send requires:

| Requirement | Reason |
|---|---|
| participant known | addressability |
| participant available | delivery expectation |
| participant not blocked | local policy |
| representation supported | interpretation |
| disclosure allowed | privacy and safety |

It does not require prior semantic topic support.

### Mediation

If representation is unsupported, the runtime may find a mediator.

```text
message(intent, naturalLanguage)
  -> mediator with translation affordance
  -> message(typedPayload, schema)
  -> target
```

Mediation is not hierarchy. It is an affordance.

### Invoke

Invoke requires a capability contract and policy approval. It is for explicit
actions, especially side-effecting work.

### Open Post

Open post goes to a coordination surface or local pub/sub style space. It is
appropriate when the caller does not know who should respond.

## Routing

Routing is plan formation, not lookup.

```text
intent/message/task
  -> representation compatibility
  -> affordance match
  -> evidence/trust view
  -> policy
  -> direct route, mediated route, open post, or reject
```

| Signal | Use |
|---|---|
| representation compatibility | hard direct-route filter |
| delivery affordance | choose best-effort, reliable, durable, or request/response path |
| aggregate roll-up | decide whether a group can act as one participant |
| affordance state | main positive or negative routing signal |
| capability contract | hard filter for invoke |
| trust view | ranking and risk input |
| constraints | risk and policy input |
| claims | weak evidence unless verified |

## Coordination Surface

Community is an optional coordination surface.

It should look more like a shared work system than a required runtime object.

```swift
public protocol CoordinationSurface: Sendable {
    func post(_ message: Message) async throws -> ThreadID
    func recordClaim(_ claim: Claim) async throws
    func recordAffordance(_ affordance: Affordance) async throws
    func recordEvidence(_ evidence: Evidence) async throws
    func assign(_ task: CoordinationTask, to participantID: ParticipantID) async throws
}
```

Use a surface when:

| Condition | Why |
|---|---|
| work is asynchronous | participants need shared state |
| context exceeds one participant | externalization helps |
| review or audit is required | history and provenance matter |
| no target is known | open post is more natural |
| physical and cognitive work must be combined | roles and evidence need tracking |

Do not create a surface when direct or mediated communication is enough.

## Use Cases

These use cases are design checks. Symbio should support all of them without
changing its core model.

### Matter Home Devices

Matter devices should not be modeled as language-capable agents. They are
participants or resources addressed through a controller participant.

```text
natural-language intent
  -> Symbio route plan
  -> Matter controller participant
  -> typed Matter command
  -> device state report
  -> evidence and affordance update
```

| Element | Symbio model |
|---|---|
| Matter controller | `ParticipantKind.controller` |
| Light, lock, thermostat | participant or controlled resource |
| Device command | `CapabilityContract` with `worldAffecting` or `safetyCritical` side effect |
| Device state | `Evidence` and `Affordance` |
| Natural language request | `MessageRepresentation.naturalLanguage` routed through a mediator or controller |
| Matter command payload | `MessageRepresentation.typedPayload` |

Example contracts:

| Contract | Side effect | Policy |
|---|---|---|
| `matter.light.level.set` | `worldAffecting` | home device control |
| `matter.lock.set` | `safetyCritical` | explicit authorization |
| `matter.thermostat.target.set` | `worldAffecting` | energy and safety policy |

The controller records evidence from device acknowledgements and state reports.
Other participants, such as robots or sensors, can add independent evidence
about the physical outcome.

### Drone Swarm

Drone swarms require a hard boundary between coordination and flight control.
Symbio coordinates mission intent, roles, affordances, evidence, and policy. It
does not perform motor control or bypass autopilot safety.

```text
operator or mission agent
  -> Symbio coordination
  -> swarm mission controller
  -> assignments, waypoints, failsafe policy
  -> drone autopilots
  -> telemetry evidence
```

| Element | Symbio model |
|---|---|
| Individual drone | `ParticipantKind.robot` |
| Squad or swarm | aggregate participant view |
| Swarm controller | `ParticipantKind.controller` |
| Mission | typed message or capability contract |
| Telemetry | evidence |
| Current capacity | affordances |
| Flight rules | policy and constraints |

Example affordances:

| Affordance | Meaning |
|---|---|
| `survey.area(zone-7)` | a drone or squad can survey a zone |
| `relay.communication(north-sector)` | a drone can act as communication relay |
| `inspect.target(tower-1)` | a drone can inspect a target |
| `formation.coverage(grid-A)` | a swarm can cover an area |
| `return.home` | a participant can safely return |

Example trust domains:

| Domain | Use |
|---|---|
| `telemetry.reliability` | weight telemetry reports |
| `navigation.accuracy` | route waypoint-sensitive tasks |
| `vision.detection` | weight object detection claims |
| `safety.compliance` | decide whether to assign risky tasks |
| `communication.latency` | choose centralized or distributed coordination |

### Robot Soccer

Robot soccer is a real-time team coordination case. Symbio should handle
tactics, role assignment, affordance sharing, and evidence. It should not own
walking, balance, ball tracking, collision avoidance, or kick actuation loops.

```text
field observations
  -> robot affordances and evidence
  -> team route or tactic plan
  -> typed intents
  -> local robot controllers
  -> outcome evidence
```

| Layer | Responsibility |
|---|---|
| Symbio team layer | role selection, team tactics, affordance sharing |
| Tactical planner | pass, press, defend, support, formation choice |
| Local controller | move, balance, kick, intercept, avoid collision |
| Reflex and safety | fall recovery, emergency stop, bounded motion |
| Evidence | ball detection, pass outcome, latency, position quality |

Example affordances:

| Affordance | Meaning |
|---|---|
| `ball.visible` | participant currently sees the ball |
| `ball.reachable` | participant can reach the ball soon |
| `kick.pass.available` | participant can make a pass |
| `kick.shot.available` | participant can shoot |
| `defense.blockingLane` | participant can block a lane |
| `goal.coverage` | participant can cover goal space |
| `formation.support` | participant can support a teammate |

Robot soccer also demonstrates why natural language is optional. During play,
typed payloads and local autonomy are usually more appropriate than language.

## Additional Design Requirements

The use cases above add requirements that the core design must satisfy.

| Requirement | Reason |
|---|---|
| Control boundary | Symbio must not bypass autopilot, reflex, actuator, or safety layers |
| Aggregate participants | swarms, squads, rooms, and teams need views in addition to individual participants |
| Freshness and expiry | affordances and evidence can become stale quickly |
| Time synchronization | telemetry, soccer observations, and device state need comparable timestamps |
| Policy before action | locks, thermostats, drones, payloads, and robot motion need explicit authorization |
| Mediation | natural language intent often must become typed payloads |
| Local autonomy | participants must handle communication loss or latency without waiting for Symbio |
| Replay and audit | physical-world actions need inspectable evidence and decisions |
| Simulation support | swarm and team strategies should be testable before real deployment |
| Safety defaults | rejected, uncertain, or stale plans should fail closed for physical actions |

These requirements imply that route planning should produce an inspectable
`RoutePlan` before execution.

```swift
public enum RoutePlanStepKind: String, Sendable, Codable, Hashable {
    case send
    case mediate
    case invoke
    case post
    case observe
    case authorize
    case reject
}

public enum PolicyDecisionState: String, Sendable, Codable, Hashable {
    case approved
    case denied
    case requiresApproval
    case notEvaluated
}

public struct PolicyDecision: Sendable, Codable, Hashable {
    public let state: PolicyDecisionState
    public let policyIDs: Set<String>
    public let reasons: [String]
    public let decidedAt: Date?
    public let expiresAt: Date?
}

public struct RoutePlanStep: Sendable, Codable, Hashable {
    public let kind: RoutePlanStepKind
    public let participantID: ParticipantID?
    public let representation: MessageRepresentation?
    public let delivery: DeliveryOption?
    public let contractID: String?
    public let aggregateExpansion: AggregateRouteExpansion?
    public let policyDecision: PolicyDecision?
    public let reasons: [String]
    public let risks: [String]
}

public struct RoutePlan: Sendable, Codable, Hashable {
    public let steps: [RoutePlanStep]
    public let requiredPolicies: Set<String>
    public let policyDecision: PolicyDecision
    public let evidenceInputs: Set<String>
    public let expiresAt: Date?
}
```

Route plans should be short-lived for physical tasks. A valid pass plan in
robot soccer or a drone survey allocation may expire in seconds.

## Runtime API Direction

```swift
public actor SymbioRuntime {
    public func observe(_ evidence: Evidence)
    public func observe(_ affordance: Affordance)
    public func view(for participantID: ParticipantID) -> ParticipantView?

    public func send(_ message: Message) async throws -> MessageReply
    public func invoke(
        _ contractID: String,
        on participantID: ParticipantID,
        payload: Data
    ) async throws -> InvocationReply

    public func planRoute(for message: Message) -> RoutePlan
    public func estimateCoordination(for task: CoordinationTask) -> CoordinationNeed
}
```

The API should make routing and mediation inspectable before execution.

## Implementation Phases

| Phase | Change |
|---|---|
| 1 | Add new value types: `ParticipantID`, `MessageRepresentation`, `DeliveryOption`, `Message`, `Claim`, `Evidence`, `Affordance`, `TrustView` |
| 2 | Add `Availability`, `ParticipantDescriptor`, and `ParticipantView` as the local social read model |
| 3 | Add aggregate participant descriptors, roll-up policies, and aggregate affordances |
| 4 | Add evidence recording and derived trust views |
| 5 | Add representation and delivery compatibility with affordance-aware routing |
| 6 | Add explicit `CapabilityContract` support for invoke |
| 7 | Add route planning that can return direct, mediated, open-post, authorized, or rejected plans |
| 8 | Add optional `CoordinationSurface` after route planning stabilizes |

## Test Strategy

| Behavior | Test |
|---|---|
| direct send does not require prior semantic topic support | available participant receives supported representation |
| direct send fails on unsupported representation | explicit representation error |
| mediator route converts natural language to typed payload | route plan includes mediator |
| invoke requires capability contract | missing contract fails |
| affordance affects routing | available affordance outranks unknown |
| expired affordance is ignored | route plan does not use expired data |
| delivery semantics are selected by task | telemetry uses best-effort, action uses request/response, evidence uses durable record |
| best-effort latest rejects stale updates | lower sequence or older frame does not update view |
| aggregate affordance rolls up member state | swarm affordance degrades when quorum is lost |
| aggregate route expands explicitly | team route produces controller or member assignment steps |
| policy is enforced before action | physical action route includes approved policy decision or authorization step |
| availability differs from affordance | reachable participant can still lack task affordance |
| trust is domain-specific | physical-action evidence does not improve analysis trust |
| trust is derived | no API accepts remote self-declared trust as authority |
| community surface is optional | simple direct route does not create surface |
