//
//  Delegate.swift
//  SwiftAgent
//
//  Created by SwiftAgent on 2025/01/15.
//

import Foundation
import OpenFoundationModels

/// A step that delegates work to a specialized subagent.
///
/// `Delegate` allows you to invoke specialized subagents as part of a Step chain,
/// integrating Claude Agent SDK-style subagent delegation with SwiftAgent's Step pattern.
///
/// ## Usage
///
/// ```swift
/// // Define a subagent
/// let codeReviewer = SubagentDefinition.codeReviewer()
///
/// // Create a delegate step
/// let reviewStep = Delegate<String, String>(
///     to: codeReviewer,
///     modelProvider: myModelProvider
/// ) { code in
///     Prompt("Please review this code:\n\n\(code)")
/// }
///
/// // Use in a chain
/// let result = try await reviewStep.run(sourceCode)
/// ```
///
/// ## Using with SubagentRegistry
///
/// ```swift
/// let registry = SubagentRegistry.build {
///     SubagentDefinition.codeReviewer()
///     SubagentDefinition.testWriter()
/// }
///
/// let delegateStep = Delegate<String, String>(
///     to: "code-reviewer",
///     registry: registry,
///     modelProvider: myModelProvider
/// ) { input in
///     Prompt("Review: \(input)")
/// }
/// ```
public struct Delegate<In: Sendable, Out: Sendable>: Step {

    public typealias Input = In
    public typealias Output = Out

    private let definition: SubagentDefinition
    private let modelProvider: any ModelProvider
    private let toolProvider: ToolProvider
    private let promptBuilder: (In) -> Prompt
    private let outputTransformer: (AgentResponse<String>) throws -> Out

    /// Creates a delegate step with a subagent definition.
    ///
    /// - Parameters:
    ///   - definition: The subagent definition.
    ///   - modelProvider: The model provider for the subagent.
    ///   - toolProvider: The tool provider (default: DefaultToolProvider).
    ///   - prompt: Prompt builder closure.
    public init(
        to definition: SubagentDefinition,
        modelProvider: any ModelProvider,
        toolProvider: ToolProvider = DefaultToolProvider(),
        @PromptBuilder prompt: @escaping (In) -> Prompt
    ) where Out == String {
        self.definition = definition
        self.modelProvider = modelProvider
        self.toolProvider = toolProvider
        self.promptBuilder = prompt
        self.outputTransformer = { $0.content }
    }

    /// Creates a delegate step with a subagent name from a registry.
    ///
    /// - Parameters:
    ///   - name: The subagent name.
    ///   - registry: The subagent registry.
    ///   - modelProvider: The model provider for the subagent.
    ///   - toolProvider: The tool provider.
    ///   - prompt: Prompt builder closure.
    public init(
        to name: String,
        registry: SubagentRegistry,
        modelProvider: any ModelProvider,
        toolProvider: ToolProvider = DefaultToolProvider(),
        @PromptBuilder prompt: @escaping (In) -> Prompt
    ) async throws where Out == String {
        guard let def = await registry.get(name) else {
            throw AgentError.subagentNotFound(name: name)
        }
        self.definition = def
        self.modelProvider = modelProvider
        self.toolProvider = toolProvider
        self.promptBuilder = prompt
        self.outputTransformer = { $0.content }
    }

    /// Creates a delegate step with a custom output transformer.
    ///
    /// - Parameters:
    ///   - definition: The subagent definition.
    ///   - modelProvider: The model provider.
    ///   - toolProvider: The tool provider.
    ///   - prompt: Prompt builder closure.
    ///   - transform: Output transformer closure.
    public init(
        to definition: SubagentDefinition,
        modelProvider: any ModelProvider,
        toolProvider: ToolProvider = DefaultToolProvider(),
        @PromptBuilder prompt: @escaping (In) -> Prompt,
        transform: @escaping (AgentResponse<String>) throws -> Out
    ) {
        self.definition = definition
        self.modelProvider = modelProvider
        self.toolProvider = toolProvider
        self.promptBuilder = prompt
        self.outputTransformer = transform
    }

    @discardableResult
    public func run(_ input: In) async throws -> Out {
        let prompt = promptBuilder(input)

        // Create invocation context
        let context = SubagentInvocationContext(
            parentModelProvider: modelProvider,
            parentTools: [],
            toolProvider: toolProvider,
            workingDirectory: FileManager.default.currentDirectoryPath
        )

        // Create a temporary registry for single invocation
        let registry = SubagentRegistry(definitions: [definition])

        // Invoke the subagent
        let response = try await registry.invoke(
            definition.name,
            prompt: prompt.description,
            context: context
        )

        return try outputTransformer(response)
    }
}

// MARK: - Delegate with AgentResponse Output

extension Delegate where Out == AgentResponse<String> {

    /// Creates a delegate step that returns the full AgentResponse.
    ///
    /// - Parameters:
    ///   - definition: The subagent definition.
    ///   - modelProvider: The model provider.
    ///   - toolProvider: The tool provider.
    ///   - prompt: Prompt builder closure.
    public init(
        to definition: SubagentDefinition,
        modelProvider: any ModelProvider,
        toolProvider: ToolProvider = DefaultToolProvider(),
        @PromptBuilder prompt: @escaping (In) -> Prompt
    ) {
        self.definition = definition
        self.modelProvider = modelProvider
        self.toolProvider = toolProvider
        self.promptBuilder = prompt
        self.outputTransformer = { $0 }
    }
}

// MARK: - Convenient Factory Methods

extension Delegate where In == String, Out == String {

    /// Creates a code review delegate.
    public static func codeReview(
        modelProvider: any ModelProvider,
        toolProvider: ToolProvider = DefaultToolProvider()
    ) -> Delegate<String, String> {
        Delegate(
            to: .codeReviewer(),
            modelProvider: modelProvider,
            toolProvider: toolProvider
        ) { code in
            Prompt(code)
        }
    }

    /// Creates a test writing delegate.
    public static func writeTests(
        modelProvider: any ModelProvider,
        toolProvider: ToolProvider = DefaultToolProvider()
    ) -> Delegate<String, String> {
        Delegate(
            to: .testWriter(),
            modelProvider: modelProvider,
            toolProvider: toolProvider
        ) { code in
            Prompt("Write tests for:\n\n\(code)")
        }
    }

    /// Creates a documentation delegate.
    public static func writeDocumentation(
        modelProvider: any ModelProvider,
        toolProvider: ToolProvider = DefaultToolProvider()
    ) -> Delegate<String, String> {
        Delegate(
            to: .documentationWriter(),
            modelProvider: modelProvider,
            toolProvider: toolProvider
        ) { code in
            Prompt("Document:\n\n\(code)")
        }
    }
}
