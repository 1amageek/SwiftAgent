import Foundation
import MCP

enum MCPToolResultRenderer {
    static func render(
        _ result: MCPToolResult,
        toolName: String
    ) throws -> String {
        var parts: [String] = []
        parts.reserveCapacity(result.content.count + (result.structuredContent == nil ? 0 : 1))

        for content in result.content {
            switch content {
            case .text(let text, _, _):
                parts.append(text)
            case .resource(let resource, _, _):
                guard let text = resource.text else {
                    throw MCPToolError.unsupportedResultContent(toolName: toolName, type: "binary resource")
                }
                parts.append(text)
            case .image:
                throw MCPToolError.unsupportedResultContent(toolName: toolName, type: "image")
            case .audio:
                throw MCPToolError.unsupportedResultContent(toolName: toolName, type: "audio")
            case .resourceLink:
                throw MCPToolError.unsupportedResultContent(toolName: toolName, type: "resource link")
            @unknown default:
                throw MCPToolError.unsupportedResultContent(toolName: toolName, type: "unknown")
            }
        }

        if let structuredContent = result.structuredContent {
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
            let data = try encoder.encode(structuredContent)
            guard let json = String(data: data, encoding: .utf8) else {
                throw MCPToolError.structuredContentIsNotUTF8(toolName: toolName)
            }
            parts.append(json)
        }

        return parts.joined(separator: "\n")
    }
}
