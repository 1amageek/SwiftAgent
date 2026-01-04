//
//  MCPDynamicTool.swift
//  SwiftAgentMCP
//
//  Created by SwiftAgent on 2025/01/31.
//

import Foundation
import SwiftAgent

// Typealias to avoid name collision with MCP.Tool
#if USE_OTHER_MODELS
public typealias LMTool = OpenFoundationModels.Tool
#else
public typealias LMTool = FoundationModels.Tool
#endif

// MARK: - MCP Dynamic Tool

/// A dynamic tool that wraps an MCP tool and conforms to Tool protocol
public struct MCPDynamicTool: LMTool, Sendable {
    public typealias Arguments = GeneratedContent
    public typealias Output = String

    /// The MCP tool definition
    public let mcpTool: MCP.Tool

    /// The MCP client to use for tool calls
    private let client: MCPClient

    /// The tool name
    public var name: String {
        mcpTool.name
    }

    /// The tool description
    public var description: String {
        mcpTool.description ?? ""
    }

    /// The parameters schema built from MCP tool's input schema
    public var parameters: GenerationSchema {
        // Convert MCP inputSchema (Value) to DynamicGenerationSchema
        do {
            let dynamicSchema = try convertValueToDynamicSchema(mcpTool.inputSchema, name: "\(name)Arguments")
            return try GenerationSchema(root: dynamicSchema, dependencies: [])
        } catch {
            // Fallback to empty schema if conversion fails
            return emptySchema()
        }
    }

    /// Creates a new dynamic tool wrapping an MCP tool
    /// - Parameters:
    ///   - mcpTool: The MCP tool definition
    ///   - client: The MCP client for making tool calls
    public init(mcpTool: MCP.Tool, client: MCPClient) {
        self.mcpTool = mcpTool
        self.client = client
    }

    /// Calls the MCP tool with the given arguments
    /// - Parameter arguments: The generated content arguments
    /// - Returns: The tool output as a string
    public func call(arguments: GeneratedContent) async throws -> String {
        // Convert GeneratedContent to [String: Value] for MCP
        let mcpArguments = try convertGeneratedContentToValue(arguments)

        let (content, isError) = try await client.callTool(name: name, arguments: mcpArguments)

        // Extract text from Tool.Content enum
        let textContent = content.compactMap { item -> String? in
            if case .text(let text) = item {
                return text
            }
            return nil
        }.joined(separator: "\n")

        if isError {
            throw MCPToolError.executionFailed(name, textContent)
        }

        return textContent
    }

    // MARK: - Private Helpers

    /// Creates an empty schema for tools without input parameters
    private func emptySchema() -> GenerationSchema {
        let dynamicSchema = DynamicGenerationSchema(
            name: "\(name)Arguments",
            description: "Arguments for \(name)",
            properties: []
        )
        // GenerationSchema requires an explicit root schema
        do {
            return try GenerationSchema(root: dynamicSchema, dependencies: [])
        } catch {
            // Empty schemas should always be valid. If this fails, it indicates
            // a bug in DynamicGenerationSchema or GenerationSchema implementation.
            fatalError("""
                Failed to create empty GenerationSchema for tool '\(name)': \(error)
                This is a framework bug - please report at https://github.com/1amageek/SwiftAgent/issues
                """)
        }
    }

    /// Converts MCP Value (JSON Schema) to DynamicGenerationSchema
    private func convertValueToDynamicSchema(_ value: Value, name: String) throws -> DynamicGenerationSchema {
        switch value {
        case .object(let obj):
            return try convertObjectToDynamicSchema(obj, name: name)
        case .string(_):
            // Simple string type
            return DynamicGenerationSchema(type: String.self)
        case .int, .double:
            return DynamicGenerationSchema(type: Double.self)
        case .bool:
            return DynamicGenerationSchema(type: Bool.self)
        case .array(let arr):
            if let first = arr.first {
                let itemSchema = try convertValueToDynamicSchema(first, name: "\(name)Item")
                return DynamicGenerationSchema(arrayOf: itemSchema)
            }
            return DynamicGenerationSchema(arrayOf: DynamicGenerationSchema(type: String.self))
        case .null:
            return DynamicGenerationSchema(type: String.self)
        case .data(mimeType: _, _):
            // Binary data - treat as string (base64 encoded)
            return DynamicGenerationSchema(type: String.self)
        }
    }

    /// Converts a JSON Schema object to DynamicGenerationSchema
    private func convertObjectToDynamicSchema(_ obj: [String: Value], name: String) throws -> DynamicGenerationSchema {
        // Check if this is a JSON Schema definition
        if let typeValue = obj["type"] {
            return try handleJSONSchemaType(obj, typeValue: typeValue, name: name)
        }

        // Otherwise treat as a simple object with properties
        var properties: [DynamicGenerationSchema.Property] = []
        for (key, val) in obj {
            let propSchema = try convertValueToDynamicSchema(val, name: key)
            properties.append(DynamicGenerationSchema.Property(
                name: key,
                description: nil,
                schema: propSchema,
                isOptional: true
            ))
        }

        return DynamicGenerationSchema(
            name: name,
            description: nil,
            properties: properties
        )
    }

    /// Handles JSON Schema type definitions
    private func handleJSONSchemaType(_ obj: [String: Value], typeValue: Value, name: String) throws -> DynamicGenerationSchema {
        guard case .string(let typeStr) = typeValue else {
            return DynamicGenerationSchema(type: String.self)
        }

        switch typeStr {
        case "object":
            return try handleObjectType(obj, name: name)
        case "array":
            return try handleArrayType(obj, name: name)
        case "string":
            return DynamicGenerationSchema(type: String.self)
        case "number", "integer":
            return DynamicGenerationSchema(type: Double.self)
        case "boolean":
            return DynamicGenerationSchema(type: Bool.self)
        default:
            return DynamicGenerationSchema(type: String.self)
        }
    }

    /// Handles JSON Schema object type
    private func handleObjectType(_ obj: [String: Value], name: String) throws -> DynamicGenerationSchema {
        var properties: [DynamicGenerationSchema.Property] = []
        var requiredProps: Set<String> = []

        // Get required properties
        if case .array(let reqArr) = obj["required"] {
            for item in reqArr {
                if case .string(let propName) = item {
                    requiredProps.insert(propName)
                }
            }
        }

        // Get properties
        if case .object(let propsObj) = obj["properties"] {
            for (propName, propValue) in propsObj {
                var propDescription: String? = nil
                if case .object(let propObj) = propValue,
                   case .string(let desc) = propObj["description"] {
                    propDescription = desc
                }

                let propSchema = try convertValueToDynamicSchema(propValue, name: propName)
                properties.append(DynamicGenerationSchema.Property(
                    name: propName,
                    description: propDescription,
                    schema: propSchema,
                    isOptional: !requiredProps.contains(propName)
                ))
            }
        }

        var schemaDescription: String? = nil
        if case .string(let desc) = obj["description"] {
            schemaDescription = desc
        }

        return DynamicGenerationSchema(
            name: name,
            description: schemaDescription,
            properties: properties
        )
    }

    /// Handles JSON Schema array type
    private func handleArrayType(_ obj: [String: Value], name: String) throws -> DynamicGenerationSchema {
        if case .object(let itemsObj) = obj["items"] {
            let itemSchema = try convertObjectToDynamicSchema(itemsObj, name: "\(name)Item")
            return DynamicGenerationSchema(arrayOf: itemSchema)
        }
        return DynamicGenerationSchema(arrayOf: DynamicGenerationSchema(type: String.self))
    }

    /// Converts GeneratedContent to MCP Value dictionary
    private func convertGeneratedContentToValue(_ content: GeneratedContent) throws -> [String: Value]? {
        switch content.kind {
        case .structure(properties: let dict, orderedKeys: _):
            var result: [String: Value] = [:]
            for (key, value) in dict {
                result[key] = try convertGeneratedContentItemToValue(value)
            }
            return result
        default:
            return nil
        }
    }

    /// Converts a single GeneratedContent item to MCP Value
    private func convertGeneratedContentItemToValue(_ content: GeneratedContent) throws -> Value {
        switch content.kind {
        case .null:
            return .null
        case .bool(let b):
            return .bool(b)
        case .number(let n):
            return .double(n)
        case .string(let s):
            return .string(s)
        case .array(let arr):
            return .array(try arr.map { try convertGeneratedContentItemToValue($0) })
        case .structure(properties: let dict, orderedKeys: _):
            var result: [String: Value] = [:]
            for (key, value) in dict {
                result[key] = try convertGeneratedContentItemToValue(value)
            }
            return .object(result)
        @unknown default:
            return .null
        }
    }
}

// MARK: - MCP Tool Error

/// Errors that can occur during MCP tool execution
public enum MCPToolError: Error, LocalizedError {
    case executionFailed(String, String)
    case invalidArguments(String)
    case schemaConversionFailed(String)

    public var errorDescription: String? {
        switch self {
        case .executionFailed(let name, let message):
            return "MCP tool '\(name)' execution failed: \(message)"
        case .invalidArguments(let message):
            return "Invalid arguments: \(message)"
        case .schemaConversionFailed(let message):
            return "Schema conversion failed: \(message)"
        }
    }
}

// MARK: - MCPClient Extension for Tools

extension MCPClient {
    /// Gets all tools from the MCP server as OpenFoundationModels-compatible tools
    /// - Returns: Array of MCPDynamicTool instances conforming to Tool protocol
    public func tools() async throws -> [MCPDynamicTool] {
        let mcpTools = try await listTools()
        return mcpTools.map { MCPDynamicTool(mcpTool: $0, client: self) }
    }

    /// Gets all tools from the MCP server as an array of any Tool
    /// - Returns: Array of tools that can be used with LanguageModelSession
    public func anyTools() async throws -> [any LMTool] {
        return try await tools()
    }
}
