import Foundation

public enum MCPServerTransportOperation: String, Sendable {
    case connect
    case receive
    case send
}

public enum MCPServerError: Error, LocalizedError, Sendable {
    case argumentEncodingFailed
    case duplicateToolName(String)
    case invalidToolName(String)
    case invalidInvocationCapacity(Int)
    case invalidMessageLimit(Int)
    case invocationCapacityExceeded(Int)
    case unexpectedToolCancellation(String)
    case transportFailure(operation: MCPServerTransportOperation, message: String)

    public var errorDescription: String? {
        switch self {
        case .argumentEncodingFailed:
            return "Failed to encode MCP arguments as UTF-8 JSON"
        case .duplicateToolName(let name):
            return "MCP server contains duplicate tool name '\(name)'"
        case .invalidToolName(let name):
            return "MCP server contains invalid tool name '\(name)'"
        case .invalidInvocationCapacity(let capacity):
            return "MCP server tool invocation capacity must be greater than zero: \(capacity)"
        case .invalidMessageLimit(let limit):
            return "MCP server message byte limit must be greater than zero: \(limit)"
        case .invocationCapacityExceeded(let capacity):
            return "MCP server reached its concurrent tool invocation capacity of \(capacity)"
        case .unexpectedToolCancellation(let name):
            return "MCP tool '\(name)' cancelled without request or server cancellation"
        case .transportFailure(let operation, let message):
            return "MCP server transport \(operation.rawValue) failed: \(message)"
        }
    }
}
