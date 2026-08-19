import SwiftAgent

/// Creates permission rules for model-facing tools owned by an MCP server.
public enum MCPPermissionRules {
    /// Matches every model-facing tool discovered from one configured server.
    public static func allTools(
        on serverName: String
    ) throws -> PermissionRule {
        PermissionRule(
            try MCPToolNamespace.qualifiedPrefix(serverName: serverName) + "*"
        )
    }
}
