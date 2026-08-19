import MCP
import SwiftAgent

/// An explicitly MCP-exposable tool. Output conversion is part of this boundary contract.
public protocol MCPServerTool: Sendable {
    var name: String { get }
    var description: String { get }
    var parameters: GenerationSchema { get }

    func call(arguments: [String: MCP.Value]?) async throws -> CallTool.Result
}
