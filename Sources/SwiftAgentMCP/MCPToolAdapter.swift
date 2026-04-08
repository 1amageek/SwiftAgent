//
//  MCPToolAdapter.swift
//  SwiftAgentMCP
//
//  Created by SwiftAgent on 2026/04/08.
//

import Foundation
import SwiftAgent

/// Bridges an ``MCPDiscoveredTool`` into SwiftAgent's `Tool` protocol.
///
/// This adapter exists only at the model runtime boundary. Discovery,
/// naming, and MCP-native invocation should stay in ``MCPDiscoveredTool``.
public struct MCPToolAdapter: Tool, Sendable {
    public typealias Arguments = GeneratedContent
    public typealias Output = String

    private let discoveredTool: MCPDiscoveredTool
    private let parametersSchema: GenerationSchema

    public init(discoveredTool: MCPDiscoveredTool) throws {
        self.discoveredTool = discoveredTool
        let dynamicSchema = try Self.convertValueToDynamicSchema(
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

        let mcpArguments = try convertGeneratedContentToValue(arguments)
        let (content, isError) = try await discoveredTool.call(arguments: mcpArguments)

        try Task.checkCancellation()
        try TurnCancellationContext.current?.checkCancellation()

        let textContent = content.compactMap { item -> String? in
            if case .text(text: let text, annotations: _, _meta: _) = item {
                return text
            }
            return nil
        }.joined(separator: "\n")

        if isError {
            throw MCPToolError.executionFailed(name, textContent)
        }

        return textContent
    }

    private static func convertValueToDynamicSchema(
        _ value: MCPValue,
        name: String
    ) throws -> DynamicGenerationSchema {
        switch value {
        case .object(let obj):
            return try convertObjectToDynamicSchema(obj, name: name)
        case .string(_):
            return DynamicGenerationSchema(type: String.self, guides: [])
        case .int, .double:
            return DynamicGenerationSchema(type: Double.self, guides: [])
        case .bool:
            return DynamicGenerationSchema(type: Bool.self, guides: [])
        case .array(let arr):
            if let first = arr.first {
                let itemSchema = try convertValueToDynamicSchema(first, name: "\(name)Item")
                return DynamicGenerationSchema(arrayOf: itemSchema)
            }
            return DynamicGenerationSchema(
                arrayOf: DynamicGenerationSchema(type: String.self, guides: [])
            )
        case .null:
            return DynamicGenerationSchema(type: String.self, guides: [])
        case .data(mimeType: _, _):
            return DynamicGenerationSchema(type: String.self, guides: [])
        }
    }

    private static func convertObjectToDynamicSchema(
        _ obj: [String: MCPValue],
        name: String
    ) throws -> DynamicGenerationSchema {
        if let typeValue = obj["type"] {
            return try handleJSONSchemaType(obj, typeValue: typeValue, name: name)
        }

        var properties: [DynamicGenerationSchema.Property] = []
        for (key, val) in obj {
            let propSchema = try convertValueToDynamicSchema(val, name: key)
            properties.append(
                DynamicGenerationSchema.Property(
                    name: key,
                    description: nil,
                    schema: propSchema,
                    isOptional: true
                )
            )
        }

        return DynamicGenerationSchema(name: name, description: nil, properties: properties)
    }

    private static func handleJSONSchemaType(
        _ obj: [String: MCPValue],
        typeValue: MCPValue,
        name: String
    ) throws -> DynamicGenerationSchema {
        guard case .string(let typeStr) = typeValue else {
            return DynamicGenerationSchema(type: String.self, guides: [])
        }

        switch typeStr {
        case "object":
            return try handleObjectType(obj, name: name)
        case "array":
            return try handleArrayType(obj, name: name)
        case "string":
            return DynamicGenerationSchema(type: String.self, guides: [])
        case "number", "integer":
            return DynamicGenerationSchema(type: Double.self, guides: [])
        case "boolean":
            return DynamicGenerationSchema(type: Bool.self, guides: [])
        default:
            return DynamicGenerationSchema(type: String.self, guides: [])
        }
    }

    private static func handleObjectType(
        _ obj: [String: MCPValue],
        name: String
    ) throws -> DynamicGenerationSchema {
        var properties: [DynamicGenerationSchema.Property] = []
        var requiredProps: Set<String> = []

        if case .array(let reqArr) = obj["required"] {
            for item in reqArr {
                if case .string(let propName) = item {
                    requiredProps.insert(propName)
                }
            }
        }

        if case .object(let propsObj) = obj["properties"] {
            for (propName, propValue) in propsObj {
                var propDescription: String?
                if case .object(let propObj) = propValue,
                   case .string(let desc) = propObj["description"] {
                    propDescription = desc
                }

                let propSchema = try convertValueToDynamicSchema(propValue, name: propName)
                properties.append(
                    DynamicGenerationSchema.Property(
                        name: propName,
                        description: propDescription,
                        schema: propSchema,
                        isOptional: !requiredProps.contains(propName)
                    )
                )
            }
        }

        var schemaDescription: String?
        if case .string(let desc) = obj["description"] {
            schemaDescription = desc
        }

        return DynamicGenerationSchema(
            name: name,
            description: schemaDescription,
            properties: properties
        )
    }

    private static func handleArrayType(
        _ obj: [String: MCPValue],
        name: String
    ) throws -> DynamicGenerationSchema {
        if case .object(let itemsObj) = obj["items"] {
            let itemSchema = try convertObjectToDynamicSchema(itemsObj, name: "\(name)Item")
            return DynamicGenerationSchema(arrayOf: itemSchema)
        }
        return DynamicGenerationSchema(
            arrayOf: DynamicGenerationSchema(type: String.self, guides: [])
        )
    }

    private func convertGeneratedContentToValue(
        _ content: GeneratedContent
    ) throws -> [String: MCPValue]? {
        switch content.kind {
        case .structure(properties: let dict, orderedKeys: _):
            var result: [String: MCPValue] = [:]
            for (key, value) in dict {
                result[key] = try convertGeneratedContentItemToValue(value)
            }
            return result
        default:
            return nil
        }
    }

    private func convertGeneratedContentItemToValue(_ content: GeneratedContent) throws -> MCPValue {
        switch content.kind {
        case .null:
            return .null
        case .bool(let value):
            return .bool(value)
        case .number(let value):
            return .double(value)
        case .string(let value):
            return .string(value)
        case .array(let values):
            return .array(try values.map { try convertGeneratedContentItemToValue($0) })
        case .structure(properties: let dict, orderedKeys: _):
            var result: [String: MCPValue] = [:]
            for (key, value) in dict {
                result[key] = try convertGeneratedContentItemToValue(value)
            }
            return .object(result)
        @unknown default:
            return .null
        }
    }
}

public enum MCPToolError: Error, LocalizedError {
    case executionFailed(String, String)

    public var errorDescription: String? {
        switch self {
        case .executionFailed(let name, let message):
            return "MCP tool '\(name)' execution failed: \(message)"
        }
    }
}
