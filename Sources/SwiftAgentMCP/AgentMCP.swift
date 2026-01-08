//
//  AgentMCP.swift
//  SwiftAgentMCP
//
//  Created by SwiftAgent on 2025/01/31.
//

/// SwiftAgentMCP provides MCP (Model Context Protocol) integration for SwiftAgent.
///
/// This module enables SwiftAgent to use tools, resources, and prompts from MCP servers.
/// MCP tools are automatically converted to Tool protocol for seamless integration.
/// Implementation is compatible with Claude Code's MCP conventions.
///
/// ## Overview
///
/// MCP (Model Context Protocol) is a standard protocol for providing tools, resources,
/// and prompts to language models. SwiftAgentMCP bridges MCP servers with SwiftAgent,
/// allowing you to use MCP tools in your agent workflows.
///
/// ## Features
///
/// - **Claude Code compatible**: Tool names use `mcp__servername__toolname` format
/// - **Configuration file support**: Load from `.mcp.json` files with `${VAR}` expansion
/// - **Multiple server management**: Connect to multiple MCP servers via `MCPClientManager`
/// - **Transport options**: stdio, HTTP, SSE (Server-Sent Events)
/// - **Authentication**: OAuth 2.0, Bearer token, Basic auth with proactive token refresh
/// - **Timeout configuration**: Configurable startup and tool execution timeouts
/// - **Server enable/disable**: Dynamically enable or disable servers
///
/// ## Quick Start
///
/// ```swift
/// import SwiftAgent
/// import SwiftAgentMCP
///
/// // Load from .mcp.json (searches ./.mcp.json then ~/.config/claude/.mcp.json)
/// let manager = try await MCPClientManager.loadDefault()
///
/// // Get all tools from all connected servers
/// let tools = try await manager.allTools()
///
/// // Use with LanguageModelSession
/// let session = LanguageModelSession(model: model, tools: tools) {
///     Instructions("...")
/// }
///
/// // Server management
/// await manager.disable(serverName: "filesystem")
/// await manager.enable(serverName: "filesystem")
///
/// // Cleanup
/// await manager.disconnectAll()
/// ```
///
/// ## Manual Configuration
///
/// ```swift
/// // Create manager
/// let manager = MCPClientManager()
///
/// // Connect to a stdio server
/// try await manager.connect(config: MCPServerConfig(
///     name: "github",
///     transport: .stdio(
///         command: "docker",
///         arguments: ["run", "-i", "--rm", "ghcr.io/github/github-mcp-server"],
///         environment: ["GITHUB_TOKEN": "..."]
///     )
/// ))
///
/// // Connect to an SSE server
/// try await manager.connect(config: MCPServerConfig(
///     name: "slack",
///     transport: .sse(
///         endpoint: URL(string: "https://slack-mcp.example.com/sse")!,
///         headers: ["Authorization": "Bearer ..."]
///     )
/// ))
///
/// // Get tools
/// let tools = try await manager.allTools()
/// // Tool names: mcp__github__get_issue, mcp__slack__send_message, etc.
/// ```
///
/// ## Configuration File (.mcp.json)
///
/// Claude Code compatible configuration format with environment variable expansion:
///
/// ```json
/// {
///   "mcpServers": {
///     "github": {
///       "command": "docker",
///       "args": ["run", "-i", "--rm", "ghcr.io/github/github-mcp-server"],
///       "env": { "GITHUB_TOKEN": "${GITHUB_TOKEN}" }
///     },
///     "slack": {
///       "url": "https://slack-mcp.example.com/sse",
///       "transport": "sse",
///       "auth": {
///         "type": "bearer",
///         "token": "${SLACK_TOKEN}"
///       }
///     },
///     "api": {
///       "url": "https://api.example.com/mcp",
///       "transport": "http",
///       "timeout": 60000,
///       "toolTimeout": 300000
///     }
///   }
/// }
/// ```
///
/// ## Transport Options
///
/// | Transport | Config | MCP SDK Implementation |
/// |-----------|--------|------------------------|
/// | stdio | `command`, `args`, `env` | `StdioTransport` |
/// | HTTP | `url`, `transport: "http"` | `HTTPClientTransport(streaming: false)` |
/// | SSE | `url`, `transport: "sse"` | `HTTPClientTransport(streaming: true)` |
///
/// ## Authentication
///
/// Supports OAuth 2.0, Bearer, and Basic authentication with proactive token refresh
/// (refreshes 5 minutes before expiration):
///
/// ```json
/// {
///   "auth": {
///     "type": "oauth2",
///     "authorizationUrl": "https://example.com/oauth/authorize",
///     "tokenUrl": "https://example.com/oauth/token",
///     "clientId": "${CLIENT_ID}",
///     "scopes": ["read", "write"]
///   }
/// }
/// ```
///
/// ## Timeout Configuration
///
/// Configure via environment variables or JSON:
///
/// | Setting | Environment Variable | JSON Field | Default |
/// |---------|---------------------|------------|---------|
/// | Startup | `MCP_TIMEOUT` | `timeout` | 30s |
/// | Tool Execution | `MCP_TOOL_TIMEOUT` | `toolTimeout` | 120s |
///
/// ## Permission Integration
///
/// MCP tool names follow the format `mcp__servername__toolname`, enabling
/// per-server permission rules:
///
/// ```swift
/// let security = SecurityConfiguration.standard
///     .allowing(.mcp("github"))      // Allow all GitHub tools (mcp__github__*)
///     .denying(.mcp("filesystem"))   // Deny filesystem tools (mcp__filesystem__*)
/// ```
///
/// ## Single Server Usage
///
/// For simple cases with a single server:
///
/// ```swift
/// let config = MCPServerConfig(
///     name: "filesystem",
///     transport: .stdio(
///         command: "/usr/local/bin/npx",
///         arguments: ["-y", "@modelcontextprotocol/server-filesystem", "/path/to/dir"]
///     ),
///     timeout: MCPTimeoutConfig(startup: .seconds(60), toolExecution: .seconds(300))
/// )
///
/// let mcpClient = try await MCPClient.connect(config: config)
/// defer { Task { await mcpClient.disconnect() } }
///
/// let mcpTools = try await mcpClient.tools()
/// ```
///
/// ## Resources and Prompts
///
/// ```swift
/// // List and read resources
/// let resources = try await mcpClient.listResources()
/// let content = try await mcpClient.resourceAsText(uri: "file:///path/to/file.txt")
///
/// // List and get prompts
/// let prompts = try await mcpClient.listPrompts()
/// let (description, messages) = try await mcpClient.getPrompt(
///     name: "code_review",
///     arguments: ["language": "swift"]
/// )
/// ```
///
/// ## Server Status
///
/// ```swift
/// // Check server status
/// let statuses = await manager.serverStatuses()
/// for status in statuses {
///     print("\(status.name): connected=\(status.isConnected), enabled=\(status.isEnabled)")
/// }
///
/// // Get specific client
/// if let githubClient = await manager.client(named: "github") {
///     let tools = try await githubClient.tools()
/// }
/// ```

import MCP

/// Typealias for MCP.Tool to avoid naming collision with SwiftAgent's Tool
public typealias MCPTool = MCP.Tool

/// Typealias for MCP.Value
public typealias MCPValue = MCP.Value
