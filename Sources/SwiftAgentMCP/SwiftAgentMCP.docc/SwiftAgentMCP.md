# ``SwiftAgentMCP``

Model Context Protocol (MCP) integration for SwiftAgent, with first-class support for both consuming external MCP servers and exposing your own tools as a server.

## Overview

`SwiftAgentMCP` provides three things:

- **MCP client integration** — discover and call tools exposed by external MCP servers, on stdio / HTTP / SSE transports.
- **MCP server hosting** — expose any `[any Tool]` collection as a fully-fledged MCP server through the ``MCPServer`` protocol and `@ToolsBuilder`.
- **Progressive tool disclosure** — group large tool collections behind `ToolSearchTool` (from `SwiftAgent`) so the model can search and dispatch tools through one stable entry point.

The module builds on the upstream [modelcontextprotocol/swift-sdk](https://github.com/modelcontextprotocol/swift-sdk) (no fork required).

### Configuration

Drop a Claude-Code-compatible `.mcp.json` next to your project:

```json
{
  "mcpServers": {
    "github": {
      "command": "docker",
      "args": ["run", "-i", "ghcr.io/github/github-mcp-server"],
      "env": {
        "GITHUB_TOKEN": "${GITHUB_TOKEN}"
      }
    }
  }
}
```

Environment variables in the form `${VAR}` are expanded at load time.

### Consuming MCP Tools

```swift
// Multi-server: load every server in the manifest
let manager = try await MCPClientManager.load(from: URL(fileURLWithPath: ".mcp.json"))
let tools = try await manager.swiftAgentTools()

// Single-server: connect to one transport directly
let client = try await MCPClient.connect(config: MCPServerConfig(
    name: "github",
    transport: .stdio(command: "docker", arguments: ["run", "-i", "..."])
))
let mcpTools = try await client.swiftAgentTools()
```

`swiftAgentTools()` returns `[any Tool]` you can pass straight into a `LanguageModelSession`.

### Hosting an MCP Server

Any `[any Tool]` becomes a server through the ``MCPServer`` protocol:

```swift
@main
struct CodingTools: MCPServer {
    @ToolsBuilder
    var tools: [any Tool] {
        ReadTool(workingDirectory: ".")
        WriteTool(workingDirectory: ".")
        GrepTool(workingDirectory: ".")
    }
}
```

The default `main()` runs over stdio. Override `run(transport:)` for custom transports (HTTP, SSE, in-process).

### Progressive Disclosure with ToolSearch

When a session has dozens of tools, declaring them all up-front bloats the model's tool schema. `ToolSearchTool` (from `SwiftAgent`) groups tools behind a single gateway: the model first searches by description, then dispatches the chosen tool through the gateway:

```swift
import SwiftAgent

let gateway = ToolSearchTool {
    ReadTool(workingDirectory: ".")
    WriteTool(workingDirectory: ".")
    GrepTool(workingDirectory: ".")
    GitTool()
    URLFetchTool()
}

let session = LanguageModelSession(
    model: .default,
    tools: gateway.gatewayTools()
) { Instructions("…") }
```

Inner tools are not registered as directly-callable tools; the gateway alone is. This works on runtimes whose tool list is fixed at session creation.

### Tool Naming and Permissions

External MCP tools follow the pattern `mcp:servername:toolname`:

```swift
.guardrail {
    Allow(.mcp("github"))           // entire server
    Allow(.tool("mcp:github:*"))    // equivalent
    Deny(.tool("mcp:github:delete*"))
}
```

### Transport Reference

| Transport | Description |
|-----------|-------------|
| `.stdio(command:arguments:)` | Subprocess over standard I/O |
| `.http(endpoint:)` | Plain HTTP request/response |
| `.sse(endpoint:)` | HTTP with Server-Sent Events streaming |

## Topics

### Client Integration

- ``MCPClient``
- ``MCPClientManager``
- ``MCPDiscoveredTool``

### Configuration

- ``MCPConfiguration``
- ``MCPServerConfig``
- ``MCPTransportConfig``

### Server Hosting

- ``MCPServer``

### Tool Adapters

- ``MCPToolAdapter``
