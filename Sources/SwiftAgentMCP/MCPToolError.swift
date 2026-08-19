import Foundation

public enum MCPToolError: Error, LocalizedError, Sendable {
    case executionFailed(String, String)
    case inputSchemaMustBeObject
    case invalidToolNamespace(server: String, tool: String)
    case duplicateToolName(server: String, tool: String)
    case invalidSchema(path: String, reason: String)
    case unsupportedSchemaType(path: String, type: String)
    case argumentsMustBeObject
    case invalidArgument(path: String, reason: String)
    case nonIntegralNumber(path: String)
    case unsupportedGeneratedContent(path: String)
    case unsupportedResultContent(toolName: String, type: String)
    case structuredContentIsNotUTF8(toolName: String)

    public var errorDescription: String? {
        switch self {
        case .executionFailed(let name, let message):
            return "MCP tool '\(name)' execution failed: \(message)"
        case .inputSchemaMustBeObject:
            return "MCP tool input schema root must be an object"
        case .invalidToolNamespace(let server, let tool):
            return "MCP tool namespace '\(server)/\(tool)' contains a reserved or invalid component"
        case .duplicateToolName(let server, let tool):
            return "MCP server '\(server)' advertised duplicate tool name '\(tool)'"
        case .invalidSchema(let path, let reason):
            return "Invalid MCP tool schema at '\(path)': \(reason)"
        case .unsupportedSchemaType(let path, let type):
            return "Unsupported MCP tool schema type '\(type)' at '\(path)'"
        case .argumentsMustBeObject:
            return "MCP tool arguments must be an object"
        case .invalidArgument(let path, let reason):
            return "Invalid MCP tool argument at '\(path)': \(reason)"
        case .nonIntegralNumber(let path):
            return "MCP integer argument at '\(path)' is not an exact Int"
        case .unsupportedGeneratedContent(let path):
            return "Generated content at '\(path)' cannot be represented as MCP JSON"
        case .unsupportedResultContent(let toolName, let type):
            return "MCP tool '\(toolName)' returned unsupported \(type) content"
        case .structuredContentIsNotUTF8(let toolName):
            return "MCP tool '\(toolName)' structured content could not be represented as UTF-8 JSON"
        }
    }
}
