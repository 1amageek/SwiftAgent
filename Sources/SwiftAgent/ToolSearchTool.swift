//
//  ToolSearchTool.swift
//  SwiftAgent
//

import Foundation

/// A gateway tool that holds a group of other tools behind one public entry
/// point.
///
/// `ToolSearchTool` implements progressive disclosure without registering the
/// inner tools as directly callable tools. The model first searches for a tool
/// schema, then calls this same gateway with the selected tool name and a JSON
/// object payload. This is necessary for runtimes whose tool definitions are
/// fixed when the session is created.
///
/// Use ``gatewayTools()`` to build the `[any Tool]` array to pass to a
/// `LanguageModelSession`.
public struct ToolSearchTool: Tool {
    public let name: String

    public var description: String {
        var text = """
        Searches and executes the grouped tools listed below.

        Use operation "search" to inspect matching tool schemas. Use operation "call" to execute \
        a selected tool through this gateway. The selected tool arguments must be provided in the \
        arguments object.

        If a call operation fails, ToolSearch returns the failure details as tool output. Read that \
        output, correct the selected tool name or arguments, and retry by calling ToolSearch again.

        Directly invoking the grouped tools is not supported; execute them through this gateway.

        Available tools:
        """
        for tool in innerTools {
            let summary = tool.description.split(separator: "\n").first.map(String.init) ?? ""
            if summary.isEmpty {
                text += "\n  \(tool.name)"
            } else {
                text += "\n  \(tool.name) — \(summary)"
            }
        }
        return text
    }

    public let innerTools: [any Tool]

    public typealias Arguments = GeneratedContent
    public typealias Output = String

    public var parameters: GenerationSchema {
        let searchArguments = DynamicGenerationSchema(
            name: "ToolSearchSearchArguments",
            description: nil,
            properties: [
                DynamicGenerationSchema.Property(
                    name: "operation",
                    description: "Search operation selector.",
                    schema: DynamicGenerationSchema(type: String.self, guides: [.constant("search")])
                ),
                DynamicGenerationSchema.Property(
                    name: "query",
                    description: "Search query for matching grouped tools.",
                    schema: DynamicGenerationSchema(type: String.self, guides: [])
                ),
                DynamicGenerationSchema.Property(
                    name: "maxResults",
                    description: "Maximum number of search results to return.",
                    schema: DynamicGenerationSchema(type: Double.self, guides: []),
                    isOptional: true
                ),
            ]
        )

        let callArguments = DynamicGenerationSchema(
            name: "ToolSearchCallArguments",
            description: nil,
            properties: [
                DynamicGenerationSchema.Property(
                    name: "operation",
                    description: "Call operation selector.",
                    schema: DynamicGenerationSchema(type: String.self, guides: [.constant("call")])
                ),
                DynamicGenerationSchema.Property(
                    name: "toolName",
                    description: "Exact grouped tool name to execute.",
                    schema: DynamicGenerationSchema(type: String.self, guides: [])
                ),
                DynamicGenerationSchema.Property(
                    name: "arguments",
                    description: "JSON object containing the selected grouped tool arguments.",
                    schema: DynamicGenerationSchema(type: GeneratedContent.self, guides: [])
                ),
            ]
        )

        let root = DynamicGenerationSchema(
            name: "ToolSearchArguments",
            description: nil,
            anyOf: [searchArguments, callArguments]
        )

        do {
            return try GenerationSchema(root: root, dependencies: [])
        } catch {
            preconditionFailure("Failed to build ToolSearch schema: \(error)")
        }
    }

    public init(name: String = "ToolSearch", @ToolsBuilder _ builder: () -> [any Tool]) {
        self.name = name
        self.innerTools = builder()
    }

    public init(name: String = "ToolSearch", tools: [any Tool]) {
        self.name = name
        self.innerTools = tools
    }

    public func call(arguments content: GeneratedContent) async throws -> String {
        let request: ToolSearchRequest
        do {
            request = try ToolSearchRequest(content)
        } catch {
            return try retryableFailureOutput(
                failure: error,
                toolName: nil,
                selectedTool: nil
            )
        }

        let normalizedOperation = request.operation?
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
        let operation = normalizedOperation ?? (request.toolName == nil ? "search" : "call")

        switch operation {
        case "search":
            return try searchOutput(request: request)
        case "call":
            return try await callSelectedTool(request: request)
        default:
            return try retryableFailureOutput(
                failure: ToolSearchToolError.unsupportedOperation(operation),
                toolName: request.toolName,
                selectedTool: tool(named: request.toolName)
            )
        }
    }

    private func searchOutput(request: ToolSearchRequest) throws -> String {
        let limit = max(1, request.maxResults ?? 5)
        let query: String
        if let toolName = request.toolName?.trimmingCharacters(in: .whitespacesAndNewlines),
           !toolName.isEmpty {
            query = "select:\(toolName)"
        } else {
            query = request.query ?? ""
        }
        var matches = Self.search(query: query, in: innerTools, limit: limit)
        if matches.isEmpty, !query.lowercased().hasPrefix("select:"), innerTools.count == 1 {
            matches = innerTools
        }

        if matches.isEmpty {
            return noMatchesOutput(query: query)
        }

        let blocks = try matches.map(Self.renderFunctionBlock(for:))
        return """
        Matching grouped tools are listed below. To execute one, call \(name) with operation "call", \
        toolName set to the selected name, and arguments containing a JSON object matching its parameters.
        \(blocks.joined(separator: "\n"))
        """
    }

    private func callSelectedTool(request: ToolSearchRequest) async throws -> String {
        guard let toolName = request.toolName?
            .trimmingCharacters(in: .whitespacesAndNewlines),
              !toolName.isEmpty else {
            return try retryableFailureOutput(
                failure: ToolSearchToolError.missingToolName,
                toolName: nil,
                selectedTool: nil
            )
        }
        guard let toolArguments = request.arguments else {
            return try retryableFailureOutput(
                failure: ToolSearchToolError.missingArguments(toolName: toolName),
                toolName: toolName,
                selectedTool: tool(named: toolName)
            )
        }

        guard let tool = tool(named: toolName) else {
            return try retryableFailureOutput(
                failure: ToolRuntimeError.unknownTool(toolName),
                toolName: toolName,
                selectedTool: nil
            )
        }

        let missingRequiredArguments = try Self.missingRequiredArguments(for: tool, arguments: toolArguments)
        if !missingRequiredArguments.isEmpty {
            return try retryableFailureOutput(
                failure: ToolSearchToolError.missingRequiredArguments(
                    toolName: toolName,
                    properties: missingRequiredArguments
                ),
                toolName: toolName,
                selectedTool: tool
            )
        }

        do {
            if let executor = ToolExecutorContext.current {
                return try await executor.execute(toolName: toolName, argumentsJSON: toolArguments.jsonString)
            }

            return try await Self.callDirect(tool: tool, arguments: toolArguments)
        } catch {
            return try retryableFailureOutput(
                failure: error,
                toolName: toolName,
                selectedTool: tool
            )
        }
    }

    private func tool(named name: String?) -> (any Tool)? {
        guard let name = name?.trimmingCharacters(in: .whitespacesAndNewlines), !name.isEmpty else {
            return nil
        }
        return innerTools.first { $0.name == name }
    }

    private func noMatchesOutput(query: String) -> String {
        let availableTools = innerTools.map { tool in
            let summary = tool.description.split(separator: "\n").first.map(String.init) ?? ""
            return summary.isEmpty ? tool.name : "\(tool.name) — \(summary)"
        }.joined(separator: "\n")

        return """
        No matching tools found for query: \(query)
        Available grouped tools:
        \(availableTools)
        Retry by calling \(name) with operation "search" and a broader capability query, or call \
        \(name) with operation "call" when you know the exact toolName and arguments object.
        """
    }

    private func retryableFailureOutput(
        failure: Error,
        toolName: String?,
        selectedTool: (any Tool)?
    ) throws -> String {
        var lines = [
            "ToolSearch could not execute the requested grouped tool call.",
            "Failure: \(Self.describe(failure))",
            "Retry by calling \(name) again with operation \"call\", toolName set to an available grouped tool, and arguments containing an object that matches the selected tool schema.",
        ]

        if let selectedTool {
            lines.append("Selected tool schema:")
            lines.append(try Self.renderFunctionBlock(for: selectedTool))
        } else {
            if let toolName = toolName?.trimmingCharacters(in: .whitespacesAndNewlines), !toolName.isEmpty {
                lines.append("Requested toolName: \(toolName)")
            }
            let names = innerTools.map(\.name).joined(separator: ", ")
            lines.append("Available grouped tool names: \(names)")
            lines.append("If the selected tool is unclear, call \(name) with operation \"search\" first.")
        }

        return lines.joined(separator: "\n")
    }

    private static func describe(_ error: Error) -> String {
        if let localizedError = error as? LocalizedError,
           let description = localizedError.errorDescription {
            return description
        }
        return String(describing: error)
    }

    // MARK: - Search

    static func search(query: String, in tools: [any Tool], limit: Int) -> [any Tool] {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)

        if trimmed.lowercased().hasPrefix("select:") {
            let list = String(trimmed.dropFirst("select:".count))
            let names = list.split(separator: ",").map {
                $0.trimmingCharacters(in: .whitespaces)
            }.filter { !$0.isEmpty }
            let byName = Dictionary(uniqueKeysWithValues: tools.map { ($0.name, $0) })
            return names.compactMap { byName[$0] }
        }

        let terms = trimmed
            .lowercased()
            .split(whereSeparator: { !$0.isLetter && !$0.isNumber })
            .map(String.init)
            .filter { !$0.isEmpty }

        if terms.isEmpty {
            return Array(tools.prefix(limit))
        }

        let scored: [(tool: any Tool, score: Int)] = tools.compactMap { tool in
            let haystack = "\(tool.name) \(tool.description)".lowercased()
            var score = 0
            for term in terms where haystack.contains(term) {
                score += tool.name.lowercased().contains(term) ? 2 : 1
            }
            return score > 0 ? (tool, score) : nil
        }

        return scored
            .sorted { $0.score > $1.score }
            .prefix(limit)
            .map(\.tool)
    }

    // MARK: - Schema rendering

    static func renderFunctionBlock(for tool: any Tool) throws -> String {
        let encoder = JSONEncoder()
        encoder.outputFormatting = []

        let data = try encoder.encode(tool.parameters)
        guard let parametersJSON = String(data: data, encoding: .utf8) else {
            throw ToolSearchToolError.invalidUTF8
        }

        let descriptionLiteral = try jsonStringLiteral(tool.description)
        let nameLiteral = try jsonStringLiteral(tool.name)
        return "<function>{\"name\":\(nameLiteral),\"description\":\(descriptionLiteral),\"parameters\":\(parametersJSON)}</function>"
    }

    private static func jsonStringLiteral(_ value: String) throws -> String {
        let data = try JSONEncoder().encode(value)
        guard let string = String(data: data, encoding: .utf8) else {
            throw ToolSearchToolError.invalidUTF8
        }
        return string
    }

    private static func missingRequiredArguments(for tool: any Tool, arguments content: GeneratedContent) throws -> [String] {
        guard case .structure(let properties, _) = content.kind else {
            return []
        }

        let data = try JSONEncoder().encode(tool.parameters)
        let object = try JSONSerialization.jsonObject(with: data)
        guard let schema = object as? [String: Any],
              let required = schema["required"] as? [String] else {
            return []
        }

        return required.filter { properties[$0] == nil }
    }

    private static func callDirect<T: Tool>(tool: T, arguments content: GeneratedContent) async throws -> String {
        let arguments = try T.Arguments(content)
        let output = try await tool.call(arguments: arguments)
        if let string = output as? String {
            return string
        }
        return String(describing: output)
    }
}

extension ToolSearchTool {
    /// Builds the gateway-only tool array to register with a
    /// `LanguageModelSession`.
    ///
    /// The returned array contains only this gateway. Inner tools are searched
    /// and executed through ``ToolSearchTool`` instead of being directly
    /// registered with deferred schemas.
    public func gatewayTools() -> [any Tool] {
        [self]
    }

    @available(*, deprecated, message: "Use gatewayTools(); direct deferred inner tools are not compatible with fixed tool-definition runtimes.")
    public func expandedTools() -> [any Tool] {
        gatewayTools()
    }
}

private struct ToolSearchRequest: Sendable {
    let operation: String?
    let query: String?
    let toolName: String?
    let arguments: GeneratedContent?
    let maxResults: Int?

    init(_ content: GeneratedContent) throws {
        guard case .structure(let properties, _) = content.kind else {
            throw ToolSearchToolError.invalidRequest
        }
        self.operation = Self.stringValue(properties["operation"])
        self.query = Self.stringValue(properties["query"])
        self.toolName = Self.stringValue(properties["toolName"])
        self.arguments = try Self.objectValue(properties["arguments"])
        self.maxResults = Self.intValue(properties["maxResults"])
    }

    private static func stringValue(_ content: GeneratedContent?) -> String? {
        guard let content else { return nil }
        if case .string(let value) = content.kind {
            return value
        }
        return nil
    }

    private static func intValue(_ content: GeneratedContent?) -> Int? {
        guard let content else { return nil }
        switch content.kind {
        case .number(let value):
            return Int(String(describing: value))
        case .string(let value):
            return Int(value)
        default:
            return nil
        }
    }

    private static func objectValue(_ content: GeneratedContent?) throws -> GeneratedContent? {
        guard let content else { return nil }
        guard case .structure = content.kind else {
            throw ToolSearchToolError.invalidArgumentsObject
        }
        return content
    }
}

public enum ToolSearchToolError: Error, LocalizedError, Sendable {
    case unsupportedOperation(String)
    case missingToolName
    case missingArguments(toolName: String)
    case missingRequiredArguments(toolName: String, properties: [String])
    case invalidRequest
    case invalidArgumentsObject
    case invalidUTF8

    public var errorDescription: String? {
        switch self {
        case .unsupportedOperation(let operation):
            return "Unsupported ToolSearch operation '\(operation)'"
        case .missingToolName:
            return "ToolSearch call operation requires toolName"
        case .missingArguments(let toolName):
            return "ToolSearch call operation requires arguments object for '\(toolName)'"
        case .missingRequiredArguments(let toolName, let properties):
            return "ToolSearch call operation for '\(toolName)' is missing required arguments: \(properties.joined(separator: ", "))"
        case .invalidRequest:
            return "ToolSearch request must be a JSON object"
        case .invalidArgumentsObject:
            return "ToolSearch call arguments must be a JSON object"
        case .invalidUTF8:
            return "ToolSearch could not convert encoded JSON data to UTF-8"
        }
    }
}
