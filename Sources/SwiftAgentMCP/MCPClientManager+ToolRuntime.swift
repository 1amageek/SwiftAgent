//
//  MCPClientManager+ToolRuntime.swift
//  SwiftAgentMCP
//

import Foundation
import SwiftAgent

extension MCPClientManager {
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
    ) async throws -> MCPSessionPayload {
        let expectedGeneration = currentCatalogGeneration()
        try requireNoCatalogTransition()
        let clients = await connectedClientSnapshot()
        try requireStableCatalog(expectedGeneration)
        var discovered: [MCPDiscoveredTool] = []
        for entry in clients {
            let tools = try await entry.client.discoveredTools()
            try requireStableCatalog(expectedGeneration)
            try await validateOwnedConnectedClient(entry)
            discovered.append(contentsOf: tools)
        }
        let adapters = try discovered.swiftAgentTools()
        let toolSearch = ToolSearchTool(name: toolSearchName, tools: adapters)

        var entries: [(server: String, text: String)] = []
        for entry in clients {
            let instructions = await entry.client.instructions
            try requireStableCatalog(expectedGeneration)
            try await validateOwnedConnectedClient(entry)
            if let text = instructions,
               !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                entries.append((server: entry.name, text: text))
            }
        }

        try requireStableCatalog(expectedGeneration)
        return MCPSessionPayload(toolSearch: toolSearch, instructions: entries)
    }
}
