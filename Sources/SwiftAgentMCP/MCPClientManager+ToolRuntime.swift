//
//  MCPClientManager+ToolRuntime.swift
//  SwiftAgentMCP
//

import SwiftAgent

extension MCPClientManager {

    /// The payload needed to expose every MCP server to a `LanguageModelSession`
    /// behind a single `ToolSearchTool` entry point.
    ///
    /// - `toolSearch` groups every MCP tool adapter behind one search entry
    ///   point. Pass `toolSearch.gatewayTools()` to `LanguageModelSession`'s
    ///   `tools:` parameter so only the gateway is registered publicly.
    /// - `instructions` contains the server-provided instructions from each
    ///   connected MCP server, keyed by server name. Callers typically fold
    ///   these into the session's system prompt verbatim.
    public struct SessionPayload: Sendable {
        /// The gateway `ToolSearchTool` wrapping all MCP adapters.
        public let toolSearch: ToolSearchTool

        /// Per-server instructions, keyed by server name, preserved in the
        /// order their servers were iterated. Empty if no server provided any.
        public let instructions: [(server: String, text: String)]

        public init(
            toolSearch: ToolSearchTool,
            instructions: [(server: String, text: String)]
        ) {
            self.toolSearch = toolSearch
            self.instructions = instructions
        }

        /// Convenience: every server's instructions joined with a blank line
        /// separator, each prefixed by a `## <server>` header. Returns `nil`
        /// when no server provided any instructions.
        public var combinedInstructionsBlock: String? {
            guard !instructions.isEmpty else { return nil }
            var parts: [String] = ["# MCP Server Instructions", ""]
            for (server, text) in instructions {
                let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
                guard !trimmed.isEmpty else { continue }
                parts.append("## \(server)")
                parts.append(trimmed)
                parts.append("")
            }
            guard parts.count > 2 else { return nil }
            return parts.joined(separator: "\n")
        }
    }

    /// Builds a session payload that exposes every MCP tool behind a single
    /// `ToolSearchTool` entry point and collects the per-server instructions.
    ///
    /// ## Example
    ///
    /// ```swift
    /// let payload = try await manager.sessionPayload()
    /// let session = LanguageModelSession(
    ///     model: model,
    ///     tools: payload.toolSearch.gatewayTools() + localTools
    /// ) {
    ///     Instructions {
    ///         "You are a helpful assistant."
    ///         if let block = payload.combinedInstructionsBlock {
    ///             block
    ///         }
    ///     }
    /// }
    /// ```
    ///
    /// - Parameter toolSearchName: The name surfaced to the model for the
    ///   gateway tool. Defaults to `"ToolSearch"`.
    public func sessionPayload(
        toolSearchName: String = "ToolSearch"
    ) async throws -> SessionPayload {
        let discovered = try await allTools()
        let adapters = try discovered.swiftAgentTools()
        let toolSearch = ToolSearchTool(name: toolSearchName, tools: adapters)

        var entries: [(server: String, text: String)] = []
        for serverName in connectedServers {
            guard let client = client(named: serverName) else { continue }
            if let text = await client.instructions,
               !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                entries.append((server: serverName, text: text))
            }
        }

        return SessionPayload(toolSearch: toolSearch, instructions: entries)
    }
}
