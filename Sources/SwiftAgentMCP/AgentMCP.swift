//
//  AgentMCP.swift
//  SwiftAgentMCP
//
//  Created by SwiftAgent on 2025/01/31.
//

/// SwiftAgentMCP provides MCP (Model Context Protocol) integration for SwiftAgent.
///
/// This module enables SwiftAgent to use tools, resources, and prompts from MCP servers.
/// MCP tools are automatically converted to OpenFoundationModels.Tool for seamless integration.
///
/// ## Overview
///
/// MCP (Model Context Protocol) is a standard protocol for providing tools, resources,
/// and prompts to language models. SwiftAgentMCP bridges MCP servers with SwiftAgent,
/// allowing you to use MCP tools in your agent workflows.
///
/// ## Usage
///
/// ```swift
/// import SwiftAgent
/// import SwiftAgentMCP
/// import OpenFoundationModels
///
/// // 1. Configure the MCP server
/// let config = MCPServerConfig(
///     name: "filesystem",
///     transport: .stdio(
///         command: "/usr/local/bin/npx",
///         arguments: ["-y", "@modelcontextprotocol/server-filesystem", "/path/to/dir"]
///     )
/// )
///
/// // 2. Connect to the MCP server
/// let mcpClient = try await MCPClient.connect(config: config)
/// defer { Task { await mcpClient.disconnect() } }
///
/// // 3. Get tools from the MCP server (OpenFoundationModels.Tool compatible)
/// let mcpTools = try await mcpClient.tools()
///
/// // 4. Use with LanguageModelSession
/// let session = LanguageModelSession(
///     model: model,
///     tools: mcpTools
/// )
///
/// // 5. Generate with tools - LLM will automatically use MCP tools
/// let generate = Generate<String, Response>(session: session) { input in
///     Prompt("List files in the directory")
/// }
/// let result = try await generate.run("test")
/// ```
///
/// ## MCP Resources
///
/// You can also read resources from MCP servers:
///
/// ```swift
/// let resources = try await mcpClient.listResources()
/// let content = try await mcpClient.resourceAsText(uri: "file:///path/to/file.txt")
/// ```
///
/// ## MCP Prompts
///
/// And fetch prompts:
///
/// ```swift
/// let prompts = try await mcpClient.listPrompts()
/// let (description, messages) = try await mcpClient.getPrompt(
///     name: "code_review",
///     arguments: ["language": "swift"]
/// )
/// ```

@_exported import MCP
