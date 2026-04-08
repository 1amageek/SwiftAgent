//
//  PluginJSONValue.swift
//  SwiftAgent
//
//  Created by SwiftAgent on 2026/04/08.
//

import Foundation

/// A recursive JSON value used for plugin manifests and tool schemas.
public enum PluginJSONValue: Sendable, Codable, Equatable {
    case object([String: PluginJSONValue])
    case array([PluginJSONValue])
    case string(String)
    case number(Double)
    case bool(Bool)
    case null

    public init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()

        if container.decodeNil() {
            self = .null
            return
        }

        if let object = try? container.decode([String: PluginJSONValue].self) {
            self = .object(object)
            return
        }

        if let array = try? container.decode([PluginJSONValue].self) {
            self = .array(array)
            return
        }

        if let string = try? container.decode(String.self) {
            self = .string(string)
            return
        }

        if let bool = try? container.decode(Bool.self) {
            self = .bool(bool)
            return
        }

        if let number = try? container.decode(Double.self) {
            self = .number(number)
            return
        }

        throw DecodingError.dataCorruptedError(
            in: container,
            debugDescription: "Unsupported JSON value"
        )
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()

        switch self {
        case .object(let object):
            try container.encode(object)
        case .array(let array):
            try container.encode(array)
        case .string(let string):
            try container.encode(string)
        case .number(let number):
            try container.encode(number)
        case .bool(let bool):
            try container.encode(bool)
        case .null:
            try container.encodeNil()
        }
    }

    public var objectValue: [String: PluginJSONValue]? {
        guard case .object(let value) = self else {
            return nil
        }
        return value
    }

    public var arrayValue: [PluginJSONValue]? {
        guard case .array(let value) = self else {
            return nil
        }
        return value
    }

    public var stringValue: String? {
        guard case .string(let value) = self else {
            return nil
        }
        return value
    }

    public func jsonString(prettyPrinted: Bool = false) throws -> String {
        let encoder = JSONEncoder()
        if prettyPrinted {
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        }
        let data = try encoder.encode(self)
        guard let string = String(data: data, encoding: .utf8) else {
            throw PluginError.invalidManifest("Failed to serialize JSON value as UTF-8")
        }
        return string
    }
}
