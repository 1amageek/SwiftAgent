import Foundation
import SwiftAgent

/// Converts one discovered MCP tool at the model-runtime boundary.
public struct MCPToolAdapter: Tool, Sendable {
    public typealias Arguments = GeneratedContent
    public typealias Output = String

    private let discoveredTool: MCPDiscoveredTool
    private let parametersSchema: GenerationSchema

    public init(discoveredTool: MCPDiscoveredTool) throws {
        self.discoveredTool = discoveredTool
        let dynamicSchema = try MCPInputSchemaConverter.convertRoot(
            discoveredTool.inputSchema,
            name: "\(discoveredTool.qualifiedName)Arguments"
        )
        self.parametersSchema = try GenerationSchema(root: dynamicSchema, dependencies: [])
    }

    public var name: String {
        discoveredTool.qualifiedName
    }

    public var description: String {
        discoveredTool.description
    }

    public var parameters: GenerationSchema {
        parametersSchema
    }

    public func call(arguments: GeneratedContent) async throws -> String {
        try Task.checkCancellation()
        try TurnCancellationContext.current?.checkCancellation()

        let mcpArguments = try MCPArgumentValueConverter.convertRoot(
            arguments,
            schema: discoveredTool.inputSchema
        )
        let result = try await discoveredTool.call(arguments: mcpArguments)

        try Task.checkCancellation()
        try TurnCancellationContext.current?.checkCancellation()

        let output = try MCPToolResultRenderer.render(result, toolName: name)
        if result.isError {
            throw MCPToolError.executionFailed(
                name,
                output.isEmpty ? "MCP server returned an error without content" : output
            )
        }
        return output
    }
}
