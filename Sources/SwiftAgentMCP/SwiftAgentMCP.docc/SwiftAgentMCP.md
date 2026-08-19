# ``SwiftAgentMCP``

An explicit lifecycle and conversion boundary between SwiftAgent and the MCP Swift SDK.

## Overview

The module keeps MCP-native discovery, pagination, resources, prompts, tool
results, transport ownership, and process ownership in the MCP layer. A tool is
converted to SwiftAgent only by ``MCPToolAdapter``. Unsupported schema and
result content fails explicitly instead of being converted to a placeholder.
The package baseline is MCP Swift SDK 0.12.1. That SDK advertises MCP protocol
version 2025-11-25; SwiftAgent does not claim support for the newer 2026-07-28
protocol until the upstream SDK exposes it.

```text
.mcp.json
    -> MCPConfiguration
    -> MCPServerConfig
    -> MCPClientManager
        -> MCPClient
            -> MCP SDK Transport
            -> optional MCPProcessLease
```

### Configuration

Only stdio and MCP Streamable HTTP are supported. Remote HTTP endpoints and
OAuth token endpoints must use HTTPS; plain HTTP is accepted only for exact
loopback hosts. Authorization is configured separately from arbitrary headers.

```json
{
  "mcpServers": {
    "local": {
      "command": "mcp-server",
      "args": ["--stdio"],
      "maximumMessageBytes": 4194304
    },
    "remote": {
      "url": "https://mcp.example.com/rpc",
      "transport": "streamable-http",
      "streaming": true,
      "auth": {
        "type": "bearer",
        "token": "${MCP_TOKEN}"
      }
    }
  }
}
```

Environment references are expanded before validation. Missing variables,
mixed transport fields, obsolete transport names, invalid timeouts, and
insecure endpoints throw ``MCPConfigurationError``. Child-process stdio is
available on macOS and Linux; iOS clients use Streamable HTTP.

Configuration decoding rejects unknown fields. Header names and values are
validated before transport creation; routing and authorization headers cannot
be smuggled through the arbitrary-header map. OAuth scope elements must each be
one RFC scope token, and only the serialized client-credentials configuration
can construct the built-in client-credentials authorizer.

### Consuming MCP Tools

```swift
let manager = try await MCPClientManager.load(
    from: URL(fileURLWithPath: ".mcp.json")
)
let discovered = try await manager.allTools()
let tools = try discovered.swiftAgentTools()

try await manager.disconnectAll()
```

Manager lifecycle mutations are serialized per server. Replacing a connection
establishes the replacement before releasing the previous owner. Disabled
entries remain registered and can be enabled later. Aggregate discovery
captures a manager catalog generation and fails with
``MCPClientError/serverCatalogChanged`` if connections are added, removed,
disabled, reconnected, or bulk-disconnected while the snapshot is being built.

For a single server:

```swift
let configuration = try MCPServerConfig(
    name: "local",
    transport: .stdio(command: "mcp-server", arguments: ["--stdio"])
)
let client = try await MCPClient.connect(config: configuration)
let tools = try await client.swiftAgentTools()
try await client.disconnect()
```

### Streamable HTTP Authorization

```swift
let configuration = try MCPServerConfig(
    name: "remote",
    transport: .streamableHTTP(
        endpoint: URL(string: "https://mcp.example.com/rpc")!,
        streaming: true
    ),
    authorization: .bearer(token: token)
)
```

Each OAuth connection creates its own authorizer state. Tool calls have a
deadline. Because MCP cancellation is advisory and SDK 0.12.1 does not expose
ownership of its internal request-send task, a deadline or caller cancellation
terminates the entire connection instead of pretending that only the request
was drained. Callers must reconnect before issuing more work. A transport owner
allows one receive stream, bounds its buffer, detects EOF as terminal, and
waits for admitted sends during disconnect. Each connection also has a
generation token, so a result from an older connection cannot be accepted after
disconnect or replacement. A stdio client owns its child process and all three
parent pipe handles through one `MCPProcessLease`; process shutdown runs with
transport shutdown so blocked pipe I/O can be released. Cleanup remains
retryable and termination failures are surfaced. `MCPClient` owns one cleanup
operation spanning the SDK client, transport owner, and process lease;
concurrent disconnect callers await it and caller cancellation cannot abandon
the underlying cleanup.

Both client and server wrappers enforce `maximumMessageBytes` before an MCP
message enters their runtime queues. The upstream SDK still assembles an HTTP
response or a newline-delimited stdio frame before handing it to this wrapper,
so allocation-before-delivery is an upstream 0.12.1 limitation rather than a
guarantee provided by SwiftAgent. Deployments must also enforce request and
response limits at the process or reverse-proxy boundary.

Streamable HTTP uses an ephemeral, cookie-free, cache-free URL session.
Redirect behavior still belongs to the upstream MCP transport. This wrapper
validates the configured endpoint and authorization inputs but cannot
reauthorize each redirect hop, so the endpoint and its redirect policy are an
administrator-controlled trust boundary. The owner can drain calls crossing
its wrapper, but it still depends on the concrete upstream transport making
active I/O return from `disconnect()`.

### Tool Naming and Permissions

Model-facing MCP tools use a collision-free
`mcp__<server-byte-count>_<server>__<tool>` encoding. Components and the
fully-qualified UTF-8 name are bounded and validated before exposure. The
same namespace owner creates server-scoped permission rules.

```swift
let githubTools = try MCPPermissionRules.allTools(on: "github")
MyStep().guardrail { Allow(githubTools) }
```

## Topics

### Client Lifecycle

- ``MCPClient``
- ``MCPClientManager``
- ``MCPClientError``
- ``MCPPermissionRules``

### Configuration

- ``MCPConfiguration``
- ``MCPServerConfig``
- ``MCPTransportConfig``
- ``MCPHTTPAuthorization``
- ``MCPTimeoutConfig``
- ``MCPConfigurationError``

### Discovery and Conversion

- ``MCPDiscoveredTool``
- ``MCPToolAdapter``
- ``MCPToolResult``
- ``MCPToolError``

### Server Hosting

- ``MCPServer``
- ``MCPServerTool``
- ``MCPTextToolAdapter``
- ``MCPServerError``

``MCPServer/run(transport:)`` enables the SDK's strict initialization mode,
waits for the receive loop instead of returning after connection setup, and
stops the SDK server on normal completion, failure, or caller cancellation.
Its transport monitor converts terminal receive and send failures that the
upstream server loop only logs into
``MCPServerError/transportFailure(operation:message:)``. Tool invocations are
owned separately from the upstream request loop and are bounded by
``MCPServer/maximumConcurrentToolInvocations``. The transport boundary uses a
bounded receive buffer, treats an unexpected clean EOF as terminal, and drains
admitted sends during its coalesced disconnect. Shutdown closes the transport,
cancels tool invocations, and drains them before `run` returns. These drains
still depend on each tool and transport honoring Swift cancellation and their
public shutdown contracts. Server implementations can lower or raise
``MCPServer/maximumMessageBytes`` explicitly.
