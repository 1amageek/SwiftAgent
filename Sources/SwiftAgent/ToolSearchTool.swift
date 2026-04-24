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
/// argument payload. This is necessary for runtimes whose tool definitions are
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
        a selected tool through this gateway. The selected tool arguments must be provided as a \
        JSON object encoded in argumentsJSON.

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

    @Generable
    public struct Arguments: Sendable {
        @Guide(description: "Operation to perform.", .anyOf(["search", "call"]))
        public let operation: String?

        @Guide(description: "Search query used when operation is search.")
        public let query: String?

        @Guide(description: "Exact grouped tool name used when operation is call.")
        public let toolName: String?

        @Guide(description: "JSON object encoded as text, used as the selected tool arguments when operation is call.")
        public let argumentsJSON: String?

        @Guide(description: "Maximum number of results to return (default: 5)")
        public let maxResults: Int?

        public init(
            operation: String? = nil,
            query: String? = nil,
            toolName: String? = nil,
            argumentsJSON: String? = nil,
            maxResults: Int? = nil
        ) {
            self.operation = operation
            self.query = query
            self.toolName = toolName
            self.argumentsJSON = argumentsJSON
            self.maxResults = maxResults
        }

        public init(query: String, maxResults: Int? = nil) {
            self.operation = "search"
            self.query = query
            self.toolName = nil
            self.argumentsJSON = nil
            self.maxResults = maxResults
        }
    }

    public typealias Output = String

    public init(name: String = "ToolSearch", @ToolsBuilder _ builder: () -> [any Tool]) {
        self.name = name
        self.innerTools = builder()
    }

    public init(name: String = "ToolSearch", tools: [any Tool]) {
        self.name = name
        self.innerTools = tools
    }

    public func call(arguments: Arguments) async throws -> String {
        let normalizedOperation = arguments.operation?
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
        let operation = normalizedOperation ?? (arguments.toolName == nil ? "search" : "call")

        switch operation {
        case "search":
            return try searchOutput(arguments: arguments)
        case "call":
            return try await callSelectedTool(arguments: arguments)
        default:
            throw ToolSearchToolError.unsupportedOperation(operation)
        }
    }

    private func searchOutput(arguments: Arguments) throws -> String {
        let limit = max(1, arguments.maxResults ?? 5)
        let query: String
        if let toolName = arguments.toolName?.trimmingCharacters(in: .whitespacesAndNewlines),
           !toolName.isEmpty {
            query = "select:\(toolName)"
        } else {
            query = arguments.query ?? ""
        }
        let matches = Self.search(query: query, in: innerTools, limit: limit)

        if matches.isEmpty {
            return "No matching tools found for query: \(query)"
        }

        let blocks = try matches.map(Self.renderFunctionBlock(for:))
        return """
        Matching grouped tools are listed below. To execute one, call \(name) with operation "call", \
        toolName set to the selected name, and argumentsJSON containing a JSON object matching its parameters.
        \(blocks.joined(separator: "\n"))
        """
    }

    private func callSelectedTool(arguments: Arguments) async throws -> String {
        guard let toolName = arguments.toolName?
            .trimmingCharacters(in: .whitespacesAndNewlines),
              !toolName.isEmpty else {
            throw ToolSearchToolError.missingToolName
        }
        guard let argumentsJSON = arguments.argumentsJSON?
            .trimmingCharacters(in: .whitespacesAndNewlines),
              !argumentsJSON.isEmpty else {
            throw ToolSearchToolError.missingArgumentsJSON(toolName: toolName)
        }

        guard let tool = innerTools.first(where: { $0.name == toolName }) else {
            throw ToolRuntimeError.unknownTool(toolName)
        }

        if let executor = ToolExecutorContext.current {
            return try await executor.execute(toolName: toolName, argumentsJSON: argumentsJSON)
        }

        return try await Self.callDirect(tool: tool, argumentsJSON: argumentsJSON)
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

    private static func callDirect<T: Tool>(tool: T, argumentsJSON: String) async throws -> String {
        let content = try GeneratedContent(json: argumentsJSON)
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

public enum ToolSearchToolError: Error, LocalizedError, Sendable {
    case unsupportedOperation(String)
    case missingToolName
    case missingArgumentsJSON(toolName: String)
    case invalidUTF8

    public var errorDescription: String? {
        switch self {
        case .unsupportedOperation(let operation):
            return "Unsupported ToolSearch operation '\(operation)'"
        case .missingToolName:
            return "ToolSearch call operation requires toolName"
        case .missingArgumentsJSON(let toolName):
            return "ToolSearch call operation requires argumentsJSON for '\(toolName)'"
        case .invalidUTF8:
            return "ToolSearch could not convert encoded JSON data to UTF-8"
        }
    }
}
