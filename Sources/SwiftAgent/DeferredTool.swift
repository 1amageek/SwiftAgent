//
//  DeferredTool.swift
//  SwiftAgent
//

import Foundation

/// Wraps an arbitrary tool so its JSONSchema is hidden from the initial
/// `toolDefinitions` but the tool remains dispatchable by name.
///
/// The wrapper preserves the inner tool's `name` and `description`, replaces
/// its `parameters` with an empty object schema, and forwards `call(arguments:)`
/// to the inner tool by decoding the raw `GeneratedContent` into the inner
/// tool's `Arguments` type. This enables progressive tool disclosure: a
/// ``ToolSearchTool`` advertises these wrappers as deferred-schema entries,
/// reveals each full JSONSchema through its search results on demand, and the
/// model then calls the wrapped tool directly once it has learned the schema.
public struct DeferredTool: Tool, Sendable {
    public typealias Arguments = GeneratedContent
    public typealias Output = Prompt

    public let name: String
    public let description: String
    public let parameters: GenerationSchema

    private let _dispatch: @Sendable (GeneratedContent) async throws -> Prompt

    public init<Inner: Tool>(wrapping tool: Inner) {
        let toolName = tool.name
        self.name = toolName
        self.description = Self.deferredDescription(for: toolName)
        self.parameters = Self.emptyObjectSchema()
        self._dispatch = { content in
            let args: Inner.Arguments
            do {
                args = try Inner.Arguments(content)
            } catch {
                throw DeferredToolError.schemaUnavailable(toolName: toolName, underlyingError: error)
            }
            let output = try await tool.call(arguments: args)
            return output.promptRepresentation
        }
    }

    public func call(arguments: GeneratedContent) async throws -> Prompt {
        try await _dispatch(arguments)
    }

    private static func deferredDescription(for toolName: String) -> String {
        """
        [DEFERRED — schema not loaded]
        Execute "\(toolName)" through ToolSearch using operation "call". Direct \
        invocation is unavailable because the argument schema is not registered \
        on this deferred wrapper.
        """
    }

    private static func emptyObjectSchema() -> GenerationSchema {
        let root = DynamicGenerationSchema(name: "DeferredArguments", description: nil, properties: [])
        do {
            return try GenerationSchema(root: root, dependencies: [])
        } catch {
            preconditionFailure("Failed to build empty GenerationSchema: \(error)")
        }
    }
}

public struct DeferredToolError: Error, LocalizedError, Sendable {
    public let toolName: String
    public let underlyingErrorDescription: String

    public init(toolName: String, underlyingError: any Error) {
        self.toolName = toolName
        self.underlyingErrorDescription = underlyingError.localizedDescription
    }

    public static func schemaUnavailable(
        toolName: String,
        underlyingError: any Error
    ) -> DeferredToolError {
        DeferredToolError(toolName: toolName, underlyingError: underlyingError)
    }

    public var errorDescription: String? {
        "Deferred schema for '\(toolName)' is unavailable; execute the tool through ToolSearch. \(underlyingErrorDescription)"
    }
}
