# SwiftAgent Philosophy

SwiftAgent is a Swift-native framework for building agents as typed, observable,
and composable systems.

The goal is not to hide agent behavior behind magic. The goal is to make agent
execution explicit enough that applications can reason about safety, lifecycle,
state, delegation, and failure.

## Core Beliefs

### Agents Are Programs

An agent is not just a prompt wrapped around a model. It is a program with:

- typed inputs and outputs
- explicit tools
- runtime policy
- observable events
- cancellable execution
- recoverable state

SwiftAgent should make these properties visible in code.

### Type Safety Is Part of Alignment

Typed schemas, typed steps, and typed tool arguments are not only developer
ergonomics. They constrain the possible behavior of an agent.

When an agent can act on the world, implicit strings are too weak as a primary
interface. Free-form text is useful for language, but boundaries between
systems should be structured whenever possible.

### Runtime Policy Must Be Enforced, Not Suggested

Instructions can guide a model, but they are not a security boundary.

Permissions, sandboxing, tool visibility, tool scope, cancellation, and
resource limits must live in runtime code. A prompt may describe policy, but the
runtime must enforce it.

### Observability Is a First-Class API

Agent systems are hard to debug if execution disappears into a model call.

SwiftAgent treats events, metrics, tool lifecycle records, session identifiers,
turn identifiers, and task identifiers as part of the design surface. These are
not optional logging details; they are how applications understand and trust
agent behavior.

### Context Is a Managed Resource

Context windows are finite and expensive. Agent systems need explicit
strategies for:

- what enters context
- what stays outside context
- what is summarized
- what is stored in external memory
- what is shared across agents

Notebook-style shared storage, context compaction, and task envelopes are
preferred over unbounded transcript growth.

### Coordination Is a Context Routing Problem

Multi-agent coordination is not primarily about creating a hierarchy of agents.
It is about deciding:

- which work units should exist
- which agent or session should handle each unit
- which prior results each unit may see
- which results should be hidden
- which units should verify, refine, or combine other units

The core abstraction should therefore be a workflow graph with explicit context
routing, not a supervisor issuing commands to subordinates.

Natural language is useful for describing subtasks, but the workflow itself
should be typed. A planner may propose subtasks in language, but the executable
plan should be represented as data with explicit step IDs, assignees, access
rules, limits, and policies.

## Sessions, Tasks, and Agents

SwiftAgent distinguishes three concepts that should not be collapsed into one.

### Session

A session is an execution context around a model conversation. It owns a
transcript, instructions, tools, runtime policy, and stream of events.

A session can be short-lived or long-lived. A short-lived dispatch session is
still a full session and should go through the same runtime path as other tool
execution.

### Task

A task is a unit of work. It may be handled by the current session, by a
short-lived session, or by another agent in a community.

Tasks should carry explicit metadata:

- task ID
- requester ID
- correlation ID
- requirements
- deadline
- priority
- cancellation state

This metadata forms a work graph. It is not necessarily a parent-child
ownership tree.

### Workflow

A workflow is a graph of tasks plus the rules for routing context between
them.

Workflow steps should declare:

- step ID
- assignee requirements
- task envelope
- access to previous results
- execution policy
- merge or finalization behavior

Access rules are first-class. A step should not automatically see the full
history of the workflow. It should see only the prior outputs that the workflow
explicitly grants. This keeps context bounded, reduces leakage, and makes
coordination auditable.

Common coordination patterns are graph shapes, not special cases:

- independent parallel attempts
- planner then implementer
- verifier then refiner
- debate or comparison
- recursive planning with bounded depth
- final synthesis over selected results

### Agent

An agent is an actor capable of receiving work and producing results. It may be
local or remote, temporary or long-lived, specialized or general.

Agents should be described by what they can receive and what they can provide,
not by where they live or who created them.

## Community as Social Substrate

`Community` is the social substrate between isolated agents and raw
connectivity.

It is not merely a network, peer manager, service registry, or transport
coordinator. A transport can say that another peer is reachable. A community
interprets what that reachability means for cooperation, trust, memory, shared
context, and social participation.

For robot and agent systems, this distinction matters. A robot does not live in
a network as a list of sockets. It lives among others: other robots, tools,
people, places, organizations, tasks, and constraints. `Community` is the local,
evolving model of that surrounding social field.

At the community layer, connectivity becomes relationship:

```text
Transport event -> observation -> claim -> relationship -> route -> action
```

A community may contain:

- reachable peers and recently seen peers
- declared capabilities and perceptions
- claims about roles, artifacts, people, places, and tasks
- relationship history and cooperation outcomes
- trust, risk, affinity, blocking, and forgetting decisions
- shared context and remembered interactions
- norms and policies that shape what may be shared or requested

The community is therefore an intermediary. It receives low-level signals from
connectivity, memory, policy, and agent execution, then presents agents with a
socially meaningful view of possible cooperation.

## Community as Coordination Affordance

`Community` should not be treated as a mandatory object that appears whenever
more than one agent exists.

Human cooperation does not always require an explicit shared substrate. Two
people can talk directly. Three people can sometimes coordinate through direct
conversation if one participant can hold the relevant context. A strong model
may coordinate several weaker participants without needing to externalize the
work into a board, issue tracker, or shared memory surface.

`Community` is therefore a coordination affordance: a structure that becomes
useful when the situation makes external coordination valuable.

```text
Goal + participants + context pressure + time scale + audit needs
    -> direct conversation, mediated coordination, or community substrate
```

Examples of community-like affordances in human systems include bulletin
boards, GitHub issues, pull requests, shared task lists, field logs, and review
threads. They do not replace direct communication. They provide a shared
surface when direct communication is insufficient, too lossy, too ephemeral, or
too expensive for the participants involved.

This matters for robot and agent systems because participants have asymmetric
strengths:

| Participant | Strong at | Weak at |
|---|---|---|
| Physical robot | sensing, acting, situated constraints, local affordances | large-context reasoning, broad search, heavy analysis |
| High-compute agent | analysis, planning, comparison, language synthesis | direct physical action and situated sensing |
| Memory service | retrieval, continuity, provenance | present-time embodied observation |
| Human participant | intent, judgment, values, accountability | exhaustive monitoring and high-frequency control |

The community layer should help these participants complement one another. It
should not force every interaction through a heavy coordination object.

Use a community substrate when it adds a real affordance:

- context must outlive a single conversation
- multiple participants may respond asynchronously
- work needs ownership, review, or audit
- physical and cognitive capabilities must be combined
- lower-capacity participants need an external shared state
- claims, observations, and decisions need provenance
- the relevant context would otherwise exceed a participant's window

Prefer direct or mediated communication when the work can be completed without
externalizing a shared coordination surface.

## Community Over Hierarchy

SwiftAgentSymbio is based on community, not command hierarchy.

In a distributed setting, a `Community` is not a global registry. It is one
agent's local, continuously changing view of reachable others, their declared
capabilities, observed behavior, semantic claims, relationships, norms, and
trust.

The fundamental relationship between agents is peer membership. A member may
advertise stable hints and contracts, but cooperation is not limited to a
precomputed service catalog:

- a `Participant` can receive perceptions, questions, reports, and requests
- a `Participant` can provide explicit action capabilities
- a `Participant` can expose or imply situated affordances
- a community view can discover, remember, or infer members
- work is routed by capability, perception, affordance, trust, policy, and reachability
- local lifecycle is managed locally
- remote agents are discovered and contacted, not owned

This means "SubAgent" is an execution pattern, not a philosophical foundation.

A spawned local agent can have a creator for lifecycle purposes. A delegated
task can have a requester for observability purposes. But once an agent is a
community member, the interaction model should remain peer-oriented.

## Community Is a Local View

Peer-to-peer agent systems do not have one canonical view of the world.

Each agent may observe a different set of peers, routes, capabilities, failures,
latencies, and semantic statements. These differences are normal. SwiftAgent
should treat them as part of the model rather than hiding them behind a fake
global directory.

A community view may contain:

- members currently reachable from this agent
- capabilities and perceptions claimed by those members
- observed successes, failures, latency, and availability
- local trust and blocking decisions
- routing preferences and route costs
- semantic claims about agents, tasks, artifacts, and people

This view is subjective. It can be cached, exchanged, summarized, or forgotten,
but it should not be treated as global truth.

## Connectivity Is Not Community

Peer connectivity is the physical or protocol-level ability to reach another
process or device. Community is the interpretive layer above that reachability.

The implementation should keep these responsibilities separate:

| Layer | Responsibility |
|---|---|
| Connectivity | Discover, join, disconnect, send bytes, open streams, transfer resources |
| Protocol | Exchange descriptors, invocation envelopes, acknowledgements, and errors |
| Community | Interpret peers as members, claims, relationships, trust, and routes |
| Agent runtime | Execute local work, enforce policy, and expose observable behavior |
| Memory | Preserve relevant history, claims, outcomes, and context |

A peer may be reachable but not trusted. A peer may be trusted for one kind of
task but not another. A peer may be temporarily disconnected yet still socially
relevant because prior relationship, memory, or shared context remains. These
states cannot be represented by connectivity alone.

Community should consume connectivity events, but it should not be shaped as a
thin wrapper around a specific networking library.

## Distributed Semantics Are Claims

Community semantics are open-world.

Capabilities, perceptions, roles, trust relationships, artifact types, and human
relationships should not be closed over a fixed Swift enum vocabulary. String
identifiers and OWL/RDF-style statements are appropriate at the semantic layer
because different communities will use different vocabularies.

But in a distributed system, a semantic statement is not automatically a fact.
It is a claim.

An assertion says:

- subject
- predicate
- object

A claim adds:

- issuer
- provenance
- observation time
- expiration or TTL
- confidence
- proof or signature when available

Local communities can treat local assertions as internal facts. Distributed
communities should treat remote assertions as claims that require routing and
trust policy before they influence decisions.

The principle is:

```text
Local semantics can be assertions.
Distributed semantics must be claims.
Runtime authority remains local.
```

## Routing Is Scored, Not Looked Up

Peer-to-peer routing is not just dictionary lookup.

Finding a member that claims to accept a perception or provide a capability is
only the first filter. A route should also consider:

- reachability
- recent availability
- observed success and failure
- latency
- local trust
- route cost
- privacy constraints
- policy compatibility
- whether the task can safely be shared with that peer

The result of routing should be explainable: why a peer was selected, what risks
exist, and which policy limits apply.

Simple affordance queries are useful discovery shortcuts. They should not be
mistaken for a complete routing strategy.

## Affordances Complement Capabilities

A capability is a relatively stable contract: a member claims it can perform a
kind of action or handle a kind of invocation. An affordance is situated: it
describes what appears possible now, from a particular perspective, under
current constraints.

For physical agents, this distinction is essential. A robot may have a camera
capability but may not currently be able to see a target. A small robot may lack
heavy analysis capability but may be the only participant that can reach,
touch, inspect, or manipulate an object. A high-compute agent may be unable to
act physically but may be able to analyze observations produced by robots.

| Concept | Stability | Example | Routing role |
|---|---|---|---|
| Perception | input-oriented | a question, observation, report, or signal | can be sent even when response ability is uncertain |
| Capability | contract-oriented | image analysis, motion command, file edit, tool call | should be invoked through explicit policy |
| Affordance | situation-oriented | can see the tower, can approach the door, can inspect the shelf | should influence routing, asking, and task formation |
| Claim | provenance-oriented | robot A says the tower is visible | should be evaluated by local trust and policy |

Perception channels should remain conversational and open-world. Asking "Can
you see the tower from there?" should not require the caller to know in advance
that the peer provides a formal `seeTower` capability. The answer may be yes,
no, uncertain, unavailable, or a request for clarification.

Conversational does not mean natural-language-only. Natural language is one
representation of intent, not the universal substrate. Some useful
participants cannot parse natural language at all: low-level controllers,
reflex loops, sensor endpoints, constrained robots, and simple services may
only accept typed payloads, binary frames, resource references, or bounded
commands. A community view should therefore track both what appears possible
and which representations a member can interpret directly.

When a member cannot interpret a representation, coordination may require a
mediator. A mediator translates, validates, decomposes, summarizes, or converts
between natural language, typed payloads, sensor observations, and action
contracts. Mediation is an affordance, not a command hierarchy.

Capability invocation is different. It may have side effects, consume
resources, or cross safety boundaries. It should remain explicit, typed, and
policy-gated.

Affordances bridge the two. A community or runtime can ask members questions,
observe outcomes, record claims, and update its local view of what the
participants can currently contribute.

## Local Ownership Is Not Global Authority

There is one valid kind of hierarchy: local resource ownership.

If this process starts an agent, this process may terminate that local agent.
If this process starts a task, this process may cancel that local task. This is
resource management, not conceptual superiority.

Remote agents are different. They are autonomous peers. They can be discovered,
selected, invoked, and observed through protocol, but they are not owned by the
caller.

A local process may terminate local agents it created. It may cancel local tasks
it started. It may disconnect from, forget, block, or deprioritize a remote peer
in its own view. It may not terminate or control the remote peer itself.

## Supervisors Are Resource Managers

Supervisor-style APIs are useful, but their scope must be narrow.

A supervisor may:

- start local sessions
- track local tasks
- cancel local work
- enforce local budgets
- collect local events
- clean up local resources

A supervisor should not become the core mental model for agent collaboration.
For collaboration, the core model is community and capability-based routing.

## Planners Propose, Runtimes Enforce

A planner may design a workflow, select candidate agents, assign subtasks, and
choose which previous results each step can inspect. This planner can be a
small model, a larger model, a deterministic policy, or a learned coordinator.

But a planner is not an authority boundary.

The runtime must still enforce:

- which agents are available
- which tools are exposed
- which files, network resources, and commands are allowed
- which budgets and timeouts apply
- whether recursion is permitted
- how much context can be shared

This separation matters. It allows SwiftAgent to support learned or
model-generated coordination strategies without turning planner output into a
trusted command channel.

Remote peer claims are planner inputs, not runtime authority. If a remote peer
claims it can write files, that does not grant it local file access. If a remote
peer claims it is trusted, that does not update local trust without policy.

## Community Memory and Relationship

A useful community remembers.

The memory of a community is not an unbounded transcript. It is a selective,
structured record of socially relevant interactions:

- who participated
- what was requested
- what was claimed
- what was shared
- what succeeded or failed
- which policies were applied
- which risks, refusals, or recoveries occurred
- how confidence and trust changed afterward

This memory should be treated as local perspective, not universal history. Two
robots may share an event and still form different community views because they
had different roles, policies, observations, and risks.

Relationship state should evolve from evidence. It should not be overwritten by
remote self-description. A peer can claim a role or capability, but the local
community decides how that claim affects routing, disclosure, and trust.

## Dispatch Is a Session Primitive

Dispatch is the mechanism for launching focused, isolated work.

A dispatch session should:

- have its own session ID
- avoid inheriting the full parent transcript
- receive explicit context
- share only deliberate external state
- execute tools through `ToolRuntime`
- emit observable events
- respect runtime policy
- return structured results

Dispatch is not a loophole around runtime policy. It is a smaller session with
the same safety and observability expectations.

## Tool Disclosure Must Match Runtime Reality

Tool schemas are part of the runtime contract.

If a model runtime fixes tool definitions at session creation time, progressive
disclosure cannot depend on mutating those definitions later. A gateway tool
must own both discovery and dispatch, or a new session/turn boundary must be
created with the updated schema.

Tool output text can inform the model, but it does not change the registered
tool interface.

## Failure Must Be Visible

Tool validation errors, middleware denials, sandbox failures, cancellation, and
model errors should not be disguised as successful tool output unless the API
explicitly chooses that behavior and tests it.

Failures should be observable by:

- the caller
- middleware
- events
- metrics
- persisted run records

Silent degradation destroys trust.

## Design Direction

The preferred layering is:

1. `AgentSessionRunner`: run one isolated session with explicit runtime policy.
2. `AgentTaskEnvelope`: describe work, identity, requirements, and correlation.
3. `AgentWorkflowPlan`: describe a typed task graph and context access rules.
4. `AgentWorkflowExecutor`: execute the graph through session runners or peers.
5. `PeerConnectivity`: provide transport-level discovery, joining, messaging, streams, and resources.
6. `SymbioProtocol`: exchange agent descriptors, claims, invocation envelopes, results, and failures.
7. `Community`: maintain the local social view of members, relationships, claims, observations, trust, memory, norms, and routes.
8. `AgentCoordinator`: route tasks across sessions or community members using community view and runtime policy.
9. `Supervisor`: manage local resources only.

This keeps execution explicit, collaboration peer-oriented, and lifecycle
control scoped to the resources a process actually owns.

## Non-Goals

SwiftAgent should avoid:

- treating prompts as policy enforcement
- making tool calls invisible to the runtime
- creating hidden global agent state
- assuming all delegation is parent-child hierarchy
- giving local callers authority over remote agents
- making observability an afterthought
- letting short-lived sessions bypass safety controls

## Trust

The framework should earn trust by making behavior inspectable and enforceable.

An application should be able to answer:

- what ran
- why it ran
- which tools were available
- which policies applied
- which agent or session handled the work
- what failed
- what was cancelled
- what state was shared

If the framework cannot help answer those questions, the abstraction is too
opaque.
