import SwiftAgent

enum MCPArgumentValueConverter {
    static func convertRoot(
        _ content: GeneratedContent,
        schema: MCPValue
    ) throws -> [String: MCPValue] {
        guard case .structure = content.kind else {
            throw MCPToolError.argumentsMustBeObject
        }
        let converted = try convert(
            content,
            schema: schema,
            path: "$arguments"
        )
        guard case .object(let arguments) = converted else {
            throw MCPToolError.argumentsMustBeObject
        }
        return arguments
    }

    private static func convert(
        _ content: GeneratedContent,
        schema: MCPValue?,
        path: String
    ) throws -> MCPValue {
        let schemaObject = try objectSchema(schema, path: path)
        let expectedType = try type(in: schemaObject, path: path)

        switch content.kind {
        case .null:
            try requireType(expectedType, allowed: ["null"], path: path)
            return .null

        case .bool(let value):
            try requireType(expectedType, allowed: ["boolean"], path: path)
            return .bool(value)

        case .number(let value):
            try requireType(
                expectedType,
                allowed: ["integer", "number"],
                path: path
            )
            if expectedType == "integer" {
                guard let integer = Int(exactly: value) else {
                    throw MCPToolError.nonIntegralNumber(path: path)
                }
                return .int(integer)
            }
            return .double(value)

        case .string(let value):
            try requireType(expectedType, allowed: ["string"], path: path)
            try validateStringEnum(value, schema: schemaObject, path: path)
            return .string(value)

        case .array(let values):
            try requireType(expectedType, allowed: ["array"], path: path)
            let itemSchema: MCPValue?
            if expectedType == "array" {
                guard let schemaObject, let items = schemaObject["items"] else {
                    throw MCPToolError.invalidSchema(
                        path: path,
                        reason: "array requires items"
                    )
                }
                itemSchema = items
            } else {
                itemSchema = nil
            }
            return .array(try values.enumerated().map { index, value in
                try convert(
                    value,
                    schema: itemSchema,
                    path: "\(path)[\(index)]"
                )
            })

        case .structure(let properties, _):
            try requireType(expectedType, allowed: ["object"], path: path)
            let schemaProperties = try schemaProperties(
                in: schemaObject,
                path: path
            )
            let required = try requiredProperties(
                in: schemaObject,
                path: path
            )
            let missing = required.subtracting(properties.keys)
            guard missing.isEmpty else {
                throw MCPToolError.invalidArgument(
                    path: path,
                    reason: "missing required properties: \(missing.sorted().joined(separator: ", "))"
                )
            }
            if disallowsAdditionalProperties(schemaObject) {
                let unknown = Set(properties.keys).subtracting(
                    schemaProperties.keys
                )
                guard unknown.isEmpty else {
                    throw MCPToolError.invalidArgument(
                        path: path,
                        reason: "unknown properties: \(unknown.sorted().joined(separator: ", "))"
                    )
                }
            }

            var result: [String: MCPValue] = [:]
            result.reserveCapacity(properties.count)
            for (name, value) in properties {
                result[name] = try convert(
                    value,
                    schema: schemaProperties[name],
                    path: "\(path).\(name)"
                )
            }
            return .object(result)

        @unknown default:
            throw MCPToolError.unsupportedGeneratedContent(path: path)
        }
    }

    private static func objectSchema(
        _ schema: MCPValue?,
        path: String
    ) throws -> [String: MCPValue]? {
        guard let schema else {
            return nil
        }
        guard case .object(let object) = schema else {
            throw MCPToolError.invalidSchema(
                path: path,
                reason: "schema node must be an object"
            )
        }
        return object
    }

    private static func type(
        in schema: [String: MCPValue]?,
        path: String
    ) throws -> String? {
        guard let value = schema?["type"] else {
            return nil
        }
        guard case .string(let type) = value else {
            throw MCPToolError.invalidSchema(
                path: path,
                reason: "type must be a string"
            )
        }
        return type
    }

    private static func requireType(
        _ expected: String?,
        allowed: Set<String>,
        path: String
    ) throws {
        guard let expected else {
            return
        }
        guard allowed.contains(expected) else {
            throw MCPToolError.invalidArgument(
                path: path,
                reason: "generated value does not match schema type '\(expected)'"
            )
        }
    }

    private static func schemaProperties(
        in schema: [String: MCPValue]?,
        path: String
    ) throws -> [String: MCPValue] {
        guard let value = schema?["properties"] else {
            return [:]
        }
        guard case .object(let properties) = value else {
            throw MCPToolError.invalidSchema(
                path: path,
                reason: "properties must be an object"
            )
        }
        return properties
    }

    private static func requiredProperties(
        in schema: [String: MCPValue]?,
        path: String
    ) throws -> Set<String> {
        guard let value = schema?["required"] else {
            return []
        }
        guard case .array(let values) = value else {
            throw MCPToolError.invalidSchema(
                path: path,
                reason: "required must be an array"
            )
        }
        return try Set(values.map { value in
            guard case .string(let name) = value else {
                throw MCPToolError.invalidSchema(
                    path: path,
                    reason: "required values must be strings"
                )
            }
            return name
        })
    }

    private static func disallowsAdditionalProperties(
        _ schema: [String: MCPValue]?
    ) -> Bool {
        guard let additionalProperties = schema?["additionalProperties"],
              case .bool(false) = additionalProperties else {
            return false
        }
        return true
    }

    private static func validateStringEnum(
        _ value: String,
        schema: [String: MCPValue]?,
        path: String
    ) throws {
        guard let enumeration = schema?["enum"] else {
            return
        }
        guard case .array(let values) = enumeration else {
            throw MCPToolError.invalidSchema(
                path: path,
                reason: "enum must be an array"
            )
        }
        let choices = try values.map { value -> String in
            guard case .string(let choice) = value else {
                throw MCPToolError.invalidSchema(
                    path: path,
                    reason: "only string enum values are supported"
                )
            }
            return choice
        }
        guard choices.contains(value) else {
            throw MCPToolError.invalidArgument(
                path: path,
                reason: "value is outside the declared enum"
            )
        }
    }
}
