/// SwiftAgentMCP owns the boundary between SwiftAgent and the upstream MCP SDK.
///
/// Client connections use either stdio or MCP Streamable HTTP. Configuration
/// is validated before any process or network resource is created. HTTP
/// authorization is separate from ordinary headers, and obsolete HTTP/SSE
/// transport cases are rejected instead of silently mapped.
///
/// ```swift
/// let manager = try await MCPClientManager.load(
///     searchPaths: [".mcp.json"]
/// )
/// let tools = try await manager.allSwiftAgentTools()
/// try await manager.disconnectAll()
/// ```
///
/// MCP-native discovery is represented by ``MCPDiscoveredTool``. Conversion
/// into a model-facing SwiftAgent tool is explicit through
/// ``MCPToolAdapter``. Model-facing names use a collision-free
/// `mcp__<server-byte-count>_<server>__<tool>` encoding.
///
/// ```swift
/// let configuration = try MCPServerConfig(
///     name: "remote",
///     transport: .streamableHTTP(
///         endpoint: URL(string: "https://mcp.example.com/rpc")!,
///         streaming: true
///     ),
///     authorization: .bearer(token: token)
/// )
/// let client = try await MCPClient.connect(config: configuration)
/// let tools = try await client.swiftAgentTools()
/// try await client.disconnect()
/// ```
///
/// `MCPClientManager` retains connection ownership. It exposes operations and
/// discovered tools rather than mutable client references, so external code
/// cannot desynchronize manager state by disconnecting an owned client.
import MCP

/// Typealias for MCP.Tool to avoid naming collision with SwiftAgent's Tool.
public typealias MCPTool = MCP.Tool

/// Typealias for MCP.Value.
public typealias MCPValue = MCP.Value
