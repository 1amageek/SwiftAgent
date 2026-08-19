import Foundation

/// Selects the MCP wire transport without exposing transport implementation objects.
public enum MCPTransportConfig: Sendable {
    case stdio(
        command: String,
        arguments: [String] = [],
        environment: [String: String]? = nil,
        workingDirectory: URL? = nil
    )

    /// MCP Streamable HTTP. `streaming` controls reception of server-initiated SSE messages.
    case streamableHTTP(
        endpoint: URL,
        streaming: Bool = true,
        headers: [String: String] = [:]
    )
}
