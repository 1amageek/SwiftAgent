//
//  MCPServer.swift
//  SwiftAgentMCP
//

import Foundation
import MCP
import SwiftAgent

// MARK: - MCPServer Protocol

/// A protocol for exposing SwiftAgent tools as an MCP server.
///
/// Any `Tool` already contains all the information MCP needs (name, description,
/// schema, call). `MCPServer` simply bridges that over a transport.
///
/// ## Minimal Usage
///
/// ```swift
/// @main
/// struct CodingTools: MCPServer {
///     @ToolsBuilder
///     var tools: [any Tool] {
///         ReadTool(workingDirectory: ".")
///         WriteTool(workingDirectory: ".")
///         GrepTool(workingDirectory: ".")
///     }
/// }
/// ```
///
/// ## Custom Transport
///
/// ```swift
/// struct MyServer: MCPServer {
///     var tools: [any Tool] { [ReadTool()] }
///
///     static func main() async throws {
///         try await Self().run(transport: StdioTransport())
///     }
/// }
/// ```
public protocol MCPServer {

    init()

    /// Server name reported to MCP clients. Defaults to the type name.
    var name: String { get }

    /// Server version reported to MCP clients. Defaults to `SwiftAgent.Info.version`.
    var version: String { get }

    /// The tools to expose via MCP.
    @ToolsBuilder var tools: [any SwiftAgent.Tool] { get }
}

// MARK: - Default Implementations

extension MCPServer {

    public var name: String { String(describing: Self.self) }

    public var version: String { SwiftAgent.Info.version }

    /// Start serving tools over the given transport.
    ///
    /// This method blocks until the transport disconnects.
    public func run(transport: any Transport) async throws {
        let server = Server(
            name: name,
            version: version,
            capabilities: .init(tools: .init())
        )

        let toolList = tools
        let toolMap: [String: any SwiftAgent.Tool] = Dictionary(
            uniqueKeysWithValues: toolList.map { ($0.name, $0) }
        )

        _ = await server
            .withMethodHandler(ListTools.self) { _ in
                let mcpTools = try toolList.map { tool -> MCPTool in
                    let schemaValue = try MCPSchemaConverter.convert(tool.parameters)
                    return MCPTool(
                        name: tool.name,
                        description: tool.description,
                        inputSchema: schemaValue
                    )
                }
                return ListTools.Result(tools: mcpTools)
            }
            .withMethodHandler(CallTool.self) { request in
                guard let tool = toolMap[request.name] else {
                    return CallTool.Result(
                        content: [.text(text: "Unknown tool: \(request.name)", annotations: nil, _meta: nil)],
                        isError: true
                    )
                }
                do {
                    let content = try MCPArgumentConverter.toGeneratedContent(request.arguments)
                    let result = try await tool.callWithGeneratedContent(content)
                    return CallTool.Result(
                        content: [.text(text: result, annotations: nil, _meta: nil)]
                    )
                } catch {
                    return CallTool.Result(
                        content: [.text(text: "Error: \(error)", annotations: nil, _meta: nil)],
                        isError: true
                    )
                }
            }

        try await server.start(transport: transport)
    }

    /// Start serving tools over stdio (default transport).
    ///
    /// This is the most common transport for MCP servers invoked by
    /// Claude Code, Cursor, and other MCP clients.
    public func run() async throws {
        try await run(transport: StdioTransport())
    }

    /// Entry point for `@main` types conforming to `MCPServer`.
    public static func main() async throws {
        try await Self().run()
    }
}

// MARK: - Tool Bridge

extension SwiftAgent.Tool {

    /// Call this tool with a `GeneratedContent` value and return the output as a string.
    ///
    /// This bridges the gap between MCP's untyped JSON arguments and
    /// the Tool protocol's typed `Arguments` associated type.
    /// Swift's existential opening resolves the concrete `Arguments` type at runtime.
    func callWithGeneratedContent(_ content: GeneratedContent) async throws -> String {
        let arguments = try Arguments(content)
        let output = try await call(arguments: arguments)
        return String(describing: output)
    }
}

// MARK: - Schema Conversion (GenerationSchema → MCP Value)

enum MCPSchemaConverter {

    /// Convert a `GenerationSchema` to an MCP `Value` representing JSON Schema.
    ///
    /// `GenerationSchema` is `Codable` and its `encode(to:)` produces standard
    /// JSON Schema via `toSchemaDictionary()`. Since `MCP.Value` is also `Codable`
    /// and represents arbitrary JSON, we round-trip through JSON data.
    static func convert(_ schema: GenerationSchema) throws -> MCPValue {
        let data = try JSONEncoder().encode(schema)
        return try JSONDecoder().decode(MCPValue.self, from: data)
    }
}

// MARK: - Argument Conversion (MCP Value → GeneratedContent)

enum MCPArgumentConverter {

    /// Convert MCP call arguments to `GeneratedContent`.
    ///
    /// MCP sends arguments as `[String: Value]?`. We wrap them in an object,
    /// encode to JSON, and parse into `GeneratedContent` which any
    /// `ConvertibleFromGeneratedContent` type can initialize from.
    static func toGeneratedContent(_ arguments: [String: MCPValue]?) throws -> GeneratedContent {
        let value: MCPValue = .object(arguments ?? [:])
        let data = try JSONEncoder().encode(value)
        guard let json = String(data: data, encoding: .utf8) else {
            throw MCPServerError.argumentEncodingFailed
        }
        return try GeneratedContent(json: json)
    }
}

// MARK: - Errors

/// Errors specific to MCPServer operation.
public enum MCPServerError: Error, LocalizedError {

    /// Failed to encode MCP arguments to JSON string.
    case argumentEncodingFailed

    public var errorDescription: String? {
        switch self {
        case .argumentEncodingFailed:
            "Failed to encode MCP arguments to JSON"
        }
    }
}
