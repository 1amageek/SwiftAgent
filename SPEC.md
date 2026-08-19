# SwiftAgent Connection and Runtime Specification

## 1. Status

This specification describes the current, intentionally breaking Agent I/O
architecture. It replaces the previous `AgentTransport`, placeholder HTTP/SSE
and WebSocket transports, and `WaitForInput`-driven CLI integration.

## 2. Responsibility Boundaries

| Layer | Owns | Does not own |
|---|---|---|
| Agent core | `Step`, `Conversation`, model/tool execution | wire framing, sockets, process I/O |
| `AgentSession` | request routing, sequential turn execution, cancellation, event emission | serialization and connection resources |
| `AgentConnection` | one bidirectional connection lifetime | conversation state and tool policy |
| concrete adapter | framing, serialization, handles/sockets, backpressure | agent orchestration |
| tool runtime | middleware, permission, sandbox, hooks | transport lifecycle |

```text
wire or terminal
    -> concrete AgentConnection
    -> RunRequest
    -> AgentSession
    -> Conversation / ToolRuntime
    -> RunEvent
    -> the same connection owner
```

## 3. Connection Contracts

The application-level boundary is split so one-way integrations do not depend
on an artificial bidirectional transport abstraction.

```swift
public protocol AgentRequestSource: Sendable {
    var supportsConcurrentReceive: Bool { get }
    func receive() async throws -> RunRequest?
}

public protocol AgentEventWriter: Sendable {
    func send(_ event: RunEvent) async throws
}

public protocol AgentConnection: AgentRequestSource, AgentEventWriter {
    func shutdown() async throws
}
```

### Required Semantics

| Operation | Contract |
|---|---|
| `receive()` value | one decoded application request |
| `receive()` returns `nil` | clean input EOF |
| `receive()` throws | decoding, framing, I/O, or overload failure |
| `send()` returns | event delivery accepted by the adapter |
| `send()` throws | output cannot be delivered; never silently discarded |
| `shutdown()` | one idempotent owner operation; all owned readers/writers and waiters are finished independently of caller cancellation |
| `supportsConcurrentReceive` | whether approval/cancel messages can arrive during turn execution |

The protocol contains no HTTP, SSE, WebSocket, NIO, or terminal types. A server
or GUI integration belongs in its own adapter target and injects a concrete
connection.

## 4. Session Execution

`AgentSession` receives requests separately from sequential turn execution.
Concurrent receive keeps approval and cancellation messages responsive while a
model turn is running. Connections that share a single interactive input
resource set `supportsConcurrentReceive` to `false`; the session then gates
receiving while the turn owns that resource. Such a connection accepts only a
`TurnGatedApprovalHandler`; an arbitrary handler is rejected because it may
open a competing reader for the same physical input.

```text
receive task
    -> text -----------------------> bounded FIFO turn queue
    -> approvalResponse ----------> correlation handler
    -> cancel ---------------------> active or pending cancellation state

bounded FIFO turn queue
    -> one active Conversation turn
    -> ordered RunEvent writes
```

The turn queue and completed/cancellation tracking are bounded. Queue overflow,
input failure, and output failure terminate the session explicitly.

## 5. Stdio Adapter

`StdioConnection` is a CLI adapter, not the universal transport. It owns:

- the asynchronous stdin reader;
- a bounded line buffer;
- CLI command interpretation (`exit` and `quit`);
- rendering `RunEvent` values to stdout/stderr;
- interactive approval input through `StdioApprovalHandler`;
- reader cancellation and waiter completion during shutdown.

It declares `supportsConcurrentReceive == false` because interactive approval
shares stdin. `StdioConnection` remains the sole stdin owner: both normal
requests and approval choices pass through its `StdioLineSource`. Passing
`CLIPermissionHandler` to this connection is rejected because `readLine()`
would create a second, uncoordinated reader. It never uses a placeholder
network implementation.

## 6. Approval

`ApprovalHandler` remains transport-neutral. `ConnectionApprovalHandler`
correlates an emitted approval request with a later
`RunRequest.approvalResponse`. A headless integration that cannot obtain
approval uses `AutoDenyApprovalHandler`; it does not turn an unanswered request
into success.

`StdioApprovalHandler` is the adapter-specific alternative for
`StdioConnection`. `TurnGatedApprovalHandler` is an explicit safety contract:
the handler may run while the receive loop is paused and must not acquire the
connection input through another reader.

```text
PermissionMiddleware (.ask)
    -> approvalRequired RunEvent
    -> ConnectionApprovalHandler waits by approval ID
    -> connection receives approvalResponse
    -> resolve or fail the pending approval
```

Closing a session must reject all unresolved approvals before returning.

## 7. Tool and Network Boundaries

All tool calls continue through `ToolRuntime` and its middleware. Network tools
are not granted ambient destination access:

- `URLFetchTool` requires a `WebDocumentFetching` implementation or an exact
  trusted-origin set;
- redirects are handled by the policy-enforced fetcher and each destination is
  reauthorized;
- an HTTP client performs exactly one non-redirecting request and enforces a
  maximum body size;
- caller headers are validated, discarded on cross-origin redirects, and
  disable response caching;
- cache hits are reauthorized and rechecked against the caller's body limit;
- cancellation does not return until the URLSession transaction invalidates;
- arbitrary untrusted destinations require an application-owned client with
  endpoint binding or an equivalent anti-rebinding guarantee.

## 8. Extension Rules

New connection adapters must:

1. live outside Agent core when they introduce a framework dependency;
2. own all wire/process resources for the connection lifetime;
3. bound inbound and outbound buffering;
4. surface clean EOF separately from failure;
5. propagate write errors;
6. document concurrent receive and half-close behavior;
7. make shutdown one idempotent owner operation that outlives caller cancellation and drains or cancels owned work.

Adding a new adapter must not add transport cases or framework imports to
`AgentSession`.

## 9. Verification Conditions

| Path | Required behavior |
|---|---|
| clean EOF | queued turns finish, then session shuts down |
| input decode/I/O failure | session reports failure and cancels owned work |
| output failure | turn/session fail; event is not reported as delivered |
| request overload | typed bounded-capacity failure |
| cancel before turn | pending cancellation applies to the matching turn only |
| cancel during turn | active cancellation token is signaled |
| connection close during approval | pending approval resumes with failure |
| non-concurrent input | only a turn-gated handler may use the connection-owned input |
| shutdown | readers, continuations, approvals, and event output are finalized |

Compilation or type existence alone is insufficient; success and failure paths
must be exercised when execution permission is granted.
