import SwiftAgent

enum MCPInputSchemaConverter {
    static func convertRoot(
        _ value: MCPValue,
        name: String
    ) throws -> DynamicGenerationSchema {
        guard case .object(let schema) = value,
              case .string("object") = schema["type"] else {
            throw MCPToolError.inputSchemaMustBeObject
        }
        try validateSupportedKeywords(
            in: schema,
            type: "object",
            path: "$input"
        )
        return try convertObject(schema, name: name, path: "$input")
    }

    private static func convert(
        _ value: MCPValue,
        name: String,
        path: String
    ) throws -> DynamicGenerationSchema {
        guard case .object(let schema) = value else {
            throw MCPToolError.invalidSchema(path: path, reason: "schema node must be an object")
        }

        guard case .string(let type) = schema["type"] else {
            throw MCPToolError.invalidSchema(path: path, reason: "type must be a string")
        }
        try validateSupportedKeywords(in: schema, type: type, path: path)

        if case .array(let enumValues) = schema["enum"] {
            guard type == "string" else {
                throw MCPToolError.invalidSchema(
                    path: path,
                    reason: "only string enums are supported"
                )
            }
            let choices = try enumValues.map { value -> String in
                guard case .string(let choice) = value else {
                    throw MCPToolError.invalidSchema(
                        path: path,
                        reason: "only string enum values are supported"
                    )
                }
                return choice
            }
            guard !choices.isEmpty else {
                throw MCPToolError.invalidSchema(path: path, reason: "enum must not be empty")
            }
            return DynamicGenerationSchema(name: name, description: description(in: schema), anyOf: choices)
        }

        switch type {
        case "object":
            return try convertObject(schema, name: name, path: path)
        case "array":
            guard let items = schema["items"] else {
                throw MCPToolError.invalidSchema(path: path, reason: "array requires items")
            }
            return DynamicGenerationSchema(
                arrayOf: try convert(items, name: "\(name)Item", path: "\(path)[]")
            )
        case "string":
            return DynamicGenerationSchema(type: String.self, guides: [])
        case "integer":
            return DynamicGenerationSchema(type: Int.self, guides: [])
        case "number":
            return DynamicGenerationSchema(type: Double.self, guides: [])
        case "boolean":
            return DynamicGenerationSchema(type: Bool.self, guides: [])
        default:
            throw MCPToolError.unsupportedSchemaType(path: path, type: type)
        }
    }

    private static func convertObject(
        _ schema: [String: MCPValue],
        name: String,
        path: String
    ) throws -> DynamicGenerationSchema {
        try validateSupportedKeywords(
            in: schema,
            type: "object",
            path: path
        )
        if let additionalProperties = schema["additionalProperties"] {
            guard case .bool(false) = additionalProperties else {
                throw MCPToolError.invalidSchema(
                    path: path,
                    reason: "only additionalProperties: false is supported"
                )
            }
        }
        let required = try requiredProperties(in: schema, path: path)
        let propertiesValue = schema["properties"] ?? .object([:])
        guard case .object(let propertySchemas) = propertiesValue else {
            throw MCPToolError.invalidSchema(path: path, reason: "properties must be an object")
        }

        let properties = try propertySchemas.keys.sorted().map { propertyName in
            guard let propertySchema = propertySchemas[propertyName] else {
                throw MCPToolError.invalidSchema(
                    path: "\(path).\(propertyName)",
                    reason: "property schema is missing"
                )
            }
            return DynamicGenerationSchema.Property(
                name: propertyName,
                description: propertyDescription(propertySchema),
                schema: try convert(
                    propertySchema,
                    name: propertyName,
                    path: "\(path).\(propertyName)"
                ),
                isOptional: !required.contains(propertyName)
            )
        }

        let unknownRequired = required.subtracting(propertySchemas.keys)
        guard unknownRequired.isEmpty else {
            throw MCPToolError.invalidSchema(
                path: path,
                reason: "required contains unknown properties: \(unknownRequired.sorted().joined(separator: ", "))"
            )
        }

        return DynamicGenerationSchema(
            name: name,
            description: description(in: schema),
            properties: properties
        )
    }

    private static func requiredProperties(
        in schema: [String: MCPValue],
        path: String
    ) throws -> Set<String> {
        guard let value = schema["required"] else {
            return []
        }
        guard case .array(let values) = value else {
            throw MCPToolError.invalidSchema(path: path, reason: "required must be an array")
        }
        return try Set(values.map { value in
            guard case .string(let name) = value else {
                throw MCPToolError.invalidSchema(path: path, reason: "required values must be strings")
            }
            return name
        })
    }

    private static func propertyDescription(_ value: MCPValue) -> String? {
        guard case .object(let schema) = value else {
            return nil
        }
        return description(in: schema)
    }

    private static func description(in schema: [String: MCPValue]) -> String? {
        guard case .string(let value) = schema["description"] else {
            return nil
        }
        return value
    }

    private static func validateSupportedKeywords(
        in schema: [String: MCPValue],
        type: String,
        path: String
    ) throws {
        var supported: Set<String> = [
            "$id",
            "$schema",
            "description",
            "title",
            "type",
        ]
        switch type {
        case "object":
            supported.formUnion([
                "additionalProperties",
                "properties",
                "required",
            ])
        case "array":
            supported.insert("items")
        case "string":
            supported.insert("enum")
        case "integer", "number", "boolean":
            break
        default:
            return
        }
        let unsupported = Set(schema.keys).subtracting(supported)
        guard unsupported.isEmpty else {
            throw MCPToolError.invalidSchema(
                path: path,
                reason: "unsupported schema keywords: \(unsupported.sorted().joined(separator: ", "))"
            )
        }
    }
}
