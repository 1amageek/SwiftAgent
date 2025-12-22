//
//  SubagentRegistry.swift
//  SwiftAgent
//
//  Created by SwiftAgent on 2025/01/15.
//

import Foundation
import OpenFoundationModels

/// A registry for managing subagents.
///
/// `SubagentRegistry` provides a central place for registering, retrieving,
/// and invoking subagents. It handles delegation with circular dependency detection.
///
/// ## Usage
///
/// ```swift
/// let registry = SubagentRegistry()
/// registry.register(.codeReviewer())
/// registry.register(.testWriter())
///
/// let response = try await registry.invoke(
///     "code-reviewer",
///     prompt: "Review this code",
///     context: context
/// )
/// ```
public actor SubagentRegistry {

    /// Registered subagent definitions.
    private var definitions: [String: SubagentDefinition] = [:]

    /// Active invocation chain (for circular dependency detection).
    private var invocationChain: [String] = []

    /// Creates an empty registry.
    public init() {}

    /// Creates a registry with initial definitions.
    public init(definitions: [SubagentDefinition]) {
        for definition in definitions {
            self.definitions[definition.name] = definition
        }
    }

    // MARK: - Registration

    /// Registers a subagent definition.
    ///
    /// - Parameter definition: The subagent definition to register.
    public func register(_ definition: SubagentDefinition) {
        definitions[definition.name] = definition
    }

    /// Registers multiple subagent definitions.
    ///
    /// - Parameter newDefinitions: The definitions to register.
    public func register(_ newDefinitions: [SubagentDefinition]) {
        for definition in newDefinitions {
            definitions[definition.name] = definition
        }
    }

    /// Unregisters a subagent by name.
    ///
    /// - Parameter name: The name of the subagent to unregister.
    /// - Returns: The removed definition, if any.
    @discardableResult
    public func unregister(_ name: String) -> SubagentDefinition? {
        definitions.removeValue(forKey: name)
    }

    /// Clears all registered subagents.
    public func clear() {
        definitions.removeAll()
    }

    // MARK: - Retrieval

    /// Gets a subagent definition by name.
    ///
    /// - Parameter name: The name of the subagent.
    /// - Returns: The definition, or nil if not found.
    public func get(_ name: String) -> SubagentDefinition? {
        definitions[name]
    }

    /// Gets all registered subagent names.
    public var registeredNames: [String] {
        Array(definitions.keys).sorted()
    }

    /// Gets all registered definitions.
    public var allDefinitions: [SubagentDefinition] {
        Array(definitions.values)
    }

    /// Checks if a subagent is registered.
    ///
    /// - Parameter name: The name to check.
    /// - Returns: `true` if registered.
    public func contains(_ name: String) -> Bool {
        definitions[name] != nil
    }

    /// The number of registered subagents.
    public var count: Int {
        definitions.count
    }

    // MARK: - Invocation

    /// Invokes a subagent with a prompt.
    ///
    /// - Parameters:
    ///   - name: The name of the subagent to invoke.
    ///   - prompt: The prompt to send to the subagent.
    ///   - context: The invocation context.
    /// - Returns: The subagent's response.
    /// - Throws: `AgentError.subagentNotFound` or `AgentError.circularDelegation`.
    public func invoke(
        _ name: String,
        prompt: String,
        context: SubagentInvocationContext
    ) async throws -> AgentResponse<String> {
        // Check if subagent exists
        guard let definition = definitions[name] else {
            throw AgentError.subagentNotFound(name: name)
        }

        // Check for circular delegation
        if invocationChain.contains(name) {
            let chain = invocationChain + [name]
            throw AgentError.circularDelegation(chain: chain)
        }

        // Add to invocation chain
        invocationChain.append(name)
        defer { invocationChain.removeLast() }

        // Create subagent session and invoke
        return try await invokeSubagent(
            definition: definition,
            prompt: prompt,
            context: context
        )
    }

    // MARK: - Private Methods

    private func invokeSubagent(
        definition: SubagentDefinition,
        prompt: String,
        context: SubagentInvocationContext
    ) async throws -> AgentResponse<String> {
        let startTime = ContinuousClock.now

        // Get model provider (from definition or parent)
        let modelProvider = definition.modelProvider ?? context.parentModelProvider

        // Get model
        let model = try await modelProvider.provideModel()

        // Resolve tools
        var tools: [any Tool] = []
        if definition.inheritParentTools {
            tools.append(contentsOf: context.parentTools)
        }

        // Add subagent's own tools
        let subagentTools = definition.tools.resolve(
            using: context.toolProvider
        )
        tools.append(contentsOf: subagentTools)

        // Create session
        let session = LanguageModelSession(
            model: model,
            tools: tools,
            instructions: definition.instructions
        )

        // Execute with turn limit
        var response: LanguageModelSession.Response<String>?
        var turns = 0
        var allTranscriptEntries: [Transcript.Entry] = []

        repeat {
            turns += 1
            response = try await session.respond(to: prompt)

            // Collect transcript entries from each turn
            if let resp = response {
                allTranscriptEntries.append(contentsOf: resp.transcriptEntries)
            }

        } while turns < definition.maxTurns && session.isResponding

        guard let finalResponse = response else {
            throw AgentError.generationFailed(reason: "Subagent produced no response")
        }

        // Extract tool calls from all transcript entries
        let extractedToolCalls = Transcript.extractToolCalls(from: allTranscriptEntries)

        let duration = ContinuousClock.now - startTime

        return AgentResponse(
            content: finalResponse.content,
            rawContent: finalResponse.rawContent,
            transcriptEntries: allTranscriptEntries,
            toolCalls: extractedToolCalls,
            duration: duration
        )
    }
}

// MARK: - Subagent Invocation Context

/// Context for subagent invocation.
public struct SubagentInvocationContext: Sendable {

    /// The parent session's model provider.
    public let parentModelProvider: any ModelProvider

    /// The parent session's tools.
    public let parentTools: [any Tool]

    /// The tool provider for resolving tool configurations.
    public let toolProvider: ToolProvider

    /// The working directory.
    public let workingDirectory: String

    /// Maximum depth of nested subagent calls.
    public let maxDepth: Int

    /// Current depth of nested calls.
    public let currentDepth: Int

    /// Creates an invocation context.
    public init(
        parentModelProvider: any ModelProvider,
        parentTools: [any Tool] = [],
        toolProvider: ToolProvider = DefaultToolProvider(),
        workingDirectory: String = FileManager.default.currentDirectoryPath,
        maxDepth: Int = 5,
        currentDepth: Int = 0
    ) {
        self.parentModelProvider = parentModelProvider
        self.parentTools = parentTools
        self.toolProvider = toolProvider
        self.workingDirectory = workingDirectory
        self.maxDepth = maxDepth
        self.currentDepth = currentDepth
    }

    /// Creates a nested context for subagent delegation.
    public func nested() -> SubagentInvocationContext {
        SubagentInvocationContext(
            parentModelProvider: parentModelProvider,
            parentTools: parentTools,
            toolProvider: toolProvider,
            workingDirectory: workingDirectory,
            maxDepth: maxDepth,
            currentDepth: currentDepth + 1
        )
    }

    /// Whether further nesting is allowed.
    public var canNest: Bool {
        currentDepth < maxDepth
    }
}

// MARK: - SubagentRegistry Builder Extension

extension SubagentRegistry {

    /// Creates a registry using a builder.
    ///
    /// ```swift
    /// let registry = SubagentRegistry.build {
    ///     SubagentDefinition.codeReviewer()
    ///     SubagentDefinition.testWriter()
    /// }
    /// ```
    public static func build(
        @SubagentDefinitionBuilder _ builder: () -> [SubagentDefinition]
    ) -> SubagentRegistry {
        SubagentRegistry(definitions: builder())
    }
}

// MARK: - Subagent Descriptions for LLM

extension SubagentRegistry {

    /// Generates a description of available subagents for the LLM.
    ///
    /// This can be included in instructions to inform the model about
    /// available subagents it can delegate to.
    public func generateSubagentDescriptions() -> String {
        guard !definitions.isEmpty else {
            return ""
        }

        var result = "## Available Subagents\n\n"
        result += "You can delegate tasks to the following specialized subagents:\n\n"

        for (name, definition) in definitions.sorted(by: { $0.key < $1.key }) {
            result += "### \(name)\n"
            result += "\(definition.subagentDescription)\n"
            result += "Tools: \(definition.tools.allowedToolNames.joined(separator: ", "))\n\n"
        }

        result += "To delegate to a subagent, use the delegate_to_subagent tool with the subagent name and a detailed prompt.\n"

        return result
    }
}
