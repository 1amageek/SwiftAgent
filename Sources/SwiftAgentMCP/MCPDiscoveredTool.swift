//
//  MCPDiscoveredTool.swift
//  SwiftAgentMCP
//
//  Created by SwiftAgent on 2026/04/08.
//

import Foundation
import SwiftAgent
import MCP

/// A first-class representation of a tool discovered from an MCP server.
///
/// `MCPDiscoveredTool` preserves the MCP-native shape: server identity,
/// original tool definition, original tool name, and raw MCP invocation path.
/// Convert it to ``MCPToolAdapter`` only when bridging into SwiftAgent's
/// `Tool` runtime for model tool-calling.
public struct MCPDiscoveredTool: Sendable {
    public let serverName: String
    public let tool: MCPTool

    private let client: MCPClient

    public init(serverName: String, tool: MCPTool, client: MCPClient) {
        self.serverName = serverName
        self.tool = tool
        self.client = client
    }

    /// Stable host-qualified tool name used for model-facing tool routing.
    public var qualifiedName: String {
        "mcp:\(serverName):\(tool.name)"
    }

    /// Original MCP tool name exposed by the server.
    public var originalName: String {
        tool.name
    }

    /// MCP tool description as advertised by the server.
    public var description: String {
        tool.description ?? ""
    }

    /// Raw MCP input schema without SwiftAgent-specific translation.
    public var inputSchema: MCPValue {
        tool.inputSchema
    }

    /// Executes the underlying MCP tool using the server-native tool name.
    public func call(arguments: [String: MCPValue]?) async throws -> ([MCP.Tool.Content], Bool) {
        try await client.callTool(name: tool.name, arguments: arguments)
    }

    /// Creates a SwiftAgent `Tool` adapter for model tool-calling.
    public func makeSwiftAgentTool() throws -> MCPToolAdapter {
        try MCPToolAdapter(discoveredTool: self)
    }
}

extension Sequence where Element == MCPDiscoveredTool {
    /// Bridges discovered MCP tools into SwiftAgent's `Tool` runtime.
    public func swiftAgentTools() throws -> [any SwiftAgent.Tool] {
        try map { try $0.makeSwiftAgentTool() as any SwiftAgent.Tool }
    }
}

extension MCPClient {
    /// Discovers MCP-native tool definitions from the server.
    public func discoveredTools() async throws -> [MCPDiscoveredTool] {
        let mcpTools = try await listTools()
        let serverName = self.name
        return mcpTools.map { MCPDiscoveredTool(serverName: serverName, tool: $0, client: self) }
    }

    /// Convenience bridge for using discovered MCP tools with `LanguageModelSession`.
    public func swiftAgentTools() async throws -> [any SwiftAgent.Tool] {
        try await discoveredTools().swiftAgentTools()
    }
}
