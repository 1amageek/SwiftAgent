# ``SwiftAgentMCP``

Model Context Protocol (MCP) integration for SwiftAgent.

## Overview

SwiftAgentMCP provides seamless integration with MCP servers, enabling agents to use external tools and services. It supports the standard MCP configuration format.

### Configuration

Create a `.mcp.json` file in your project root:

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

### Loading MCP Tools

```swift
// Load from search paths
let manager = try await MCPClientManager.load(searchPaths: ["./mcp.json"])
let tools = try await manager.allTools()

// Connect to a single server
let client = try await MCPClient.connect(config: MCPServerConfig(
    name: "github",
    transport: .stdio(command: "docker", arguments: ["run", "-i", "..."])
))
let mcpTools = try await client.tools()
```

### Tool Naming Convention

MCP tools follow the naming pattern: `mcp__servername__toolname`

```swift
// Permission rules for MCP tools
.allowing(.mcp("github"))           // Allow all tools from github server
.allowing(.tool("mcp__github__*"))  // Same as above
```

### Transport Types

| Transport | Description |
|-----------|-------------|
| `.stdio()` | Standard I/O communication |
| `.http()` | HTTP transport |
| `.sse()` | Server-Sent Events |

## Topics

### Client Management

- ``MCPClientManager``
- ``MCPClient``

### Configuration

- ``MCPConfiguration``
- ``MCPServerConfig``

### Tools

- ``MCPDynamicTool``

### Authentication

- ``MCPAuth``
