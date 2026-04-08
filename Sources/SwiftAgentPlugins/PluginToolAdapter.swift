//
//  PluginToolAdapter.swift
//  SwiftAgent
//
//  Created by SwiftAgent on 2026/04/08.
//

import Foundation
import SwiftAgent

/// Bridges a plugin-native tool into SwiftAgent's `Tool` protocol.
public struct PluginToolAdapter: Tool, Sendable {
    public typealias Arguments = GeneratedContent
    public typealias Output = String

    private let pluginTool: PluginTool
    private let parametersSchema: GenerationSchema

    public init(pluginTool: PluginTool) throws {
        self.pluginTool = pluginTool
        let schema = try Self.convertJSONSchema(
            pluginTool.definition.inputSchema,
            name: "\(pluginTool.definition.name)Arguments"
        )
        self.parametersSchema = try GenerationSchema(root: schema, dependencies: [])
    }

    public var name: String {
        pluginTool.definition.name
    }

    public var description: String {
        pluginTool.definition.description ?? "Invoke plugin tool `\(pluginTool.definition.name)`."
    }

    public var parameters: GenerationSchema {
        parametersSchema
    }

    public func call(arguments: GeneratedContent) async throws -> String {
        try await pluginTool.execute(argumentsJSON: arguments.jsonString)
    }

    private static func convertJSONSchema(
        _ schema: PluginJSONValue,
        name: String
    ) throws -> DynamicGenerationSchema {
        guard let object = schema.objectValue else {
            throw PluginError.invalidManifest("plugin tool `\(name)` schema must be a JSON object")
        }

        if let type = object["type"]?.stringValue {
            switch type {
            case "object":
                return try convertObjectSchema(object, name: name)
            case "array":
                return try convertArraySchema(object, name: name)
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

        return try convertObjectSchema(object, name: name)
    }

    private static func convertObjectSchema(
        _ object: [String: PluginJSONValue],
        name: String
    ) throws -> DynamicGenerationSchema {
        var properties: [DynamicGenerationSchema.Property] = []
        var required = Set<String>()

        if let requiredEntries = object["required"]?.arrayValue {
            for entry in requiredEntries {
                if let key = entry.stringValue {
                    required.insert(key)
                }
            }
        }

        if let propertyObject = object["properties"]?.objectValue {
            for (propertyName, propertySchemaValue) in propertyObject {
                let propertyObjectValue = propertySchemaValue.objectValue
                let propertyDescription = propertyObjectValue?["description"]?.stringValue
                let propertySchema = try convertNestedSchema(propertySchemaValue, name: propertyName)
                properties.append(
                    DynamicGenerationSchema.Property(
                        name: propertyName,
                        description: propertyDescription,
                        schema: propertySchema,
                        isOptional: !required.contains(propertyName)
                    )
                )
            }
        }

        return DynamicGenerationSchema(
            name: name,
            description: object["description"]?.stringValue,
            properties: properties
        )
    }

    private static func convertArraySchema(
        _ object: [String: PluginJSONValue],
        name: String
    ) throws -> DynamicGenerationSchema {
        if let items = object["items"] {
            let itemSchema = try convertNestedSchema(items, name: "\(name)Item")
            return DynamicGenerationSchema(arrayOf: itemSchema)
        }

        return DynamicGenerationSchema(
            arrayOf: DynamicGenerationSchema(type: String.self, guides: [])
        )
    }

    private static func convertNestedSchema(
        _ value: PluginJSONValue,
        name: String
    ) throws -> DynamicGenerationSchema {
        switch value {
        case .object:
            return try convertJSONSchema(value, name: name)
        case .string:
            return DynamicGenerationSchema(type: String.self, guides: [])
        case .number:
            return DynamicGenerationSchema(type: Double.self, guides: [])
        case .bool:
            return DynamicGenerationSchema(type: Bool.self, guides: [])
        case .array(let values):
            if let first = values.first {
                let itemSchema = try convertNestedSchema(first, name: "\(name)Item")
                return DynamicGenerationSchema(arrayOf: itemSchema)
            }
            return DynamicGenerationSchema(
                arrayOf: DynamicGenerationSchema(type: String.self, guides: [])
            )
        case .null:
            return DynamicGenerationSchema(type: String.self, guides: [])
        }
    }
}

extension PluginToolAdapter: ToolContextMetadataProvider {
    public func toolContextMetadata(argumentsJSON _: String) -> [String: String] {
        [
            "pluginID": pluginTool.pluginID,
            "pluginName": pluginTool.pluginName,
            ToolAuthorizationMetadata.minimumPermissionModeKey: pluginTool.requiredPermission.permissionMode.rawValue,
        ]
    }
}
