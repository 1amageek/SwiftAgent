import Foundation
import SwiftAgent

/// The payload needed to expose MCP servers to a `LanguageModelSession` through one gateway.
public struct MCPSessionPayload: Sendable {
    /// The gateway `ToolSearchTool` wrapping all MCP adapters.
    public let toolSearch: ToolSearchTool

    /// Per-server instructions, keyed by server name.
    public let instructions: [(server: String, text: String)]

    public init(
        toolSearch: ToolSearchTool,
        instructions: [(server: String, text: String)]
    ) {
        self.toolSearch = toolSearch
        self.instructions = instructions
    }

    /// Every server's instructions joined under deterministic server headers.
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
