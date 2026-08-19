import MCP

/// Preserves every MCP tool result channel until an application adapter chooses a representation.
public struct MCPToolResult: Sendable {
    public let content: [MCP.Tool.Content]
    public let structuredContent: MCP.Value?
    public let isError: Bool

    public init(
        content: [MCP.Tool.Content],
        structuredContent: MCP.Value?,
        isError: Bool
    ) {
        self.content = content
        self.structuredContent = structuredContent
        self.isError = isError
    }
}
