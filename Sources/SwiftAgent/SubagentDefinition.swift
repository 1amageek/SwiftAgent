//
//  SubagentDefinition.swift
//  SwiftAgent
//
//  Created by SwiftAgent on 2025/01/15.
//

import Foundation
import OpenFoundationModels

/// Definition of a subagent that can be delegated tasks.
///
/// Subagents are specialized agents that can be invoked by a parent agent
/// to handle specific types of tasks. This is similar to Claude Agent SDK's
/// `agents` configuration option.
///
/// ## Usage
///
/// ```swift
/// let codeReviewer = SubagentDefinition(
///     name: "code-reviewer",
///     description: "Reviews code for issues and improvements",
///     instructions: Instructions {
///         "You are an expert code reviewer."
///         "Focus on: bugs, performance, readability, and security."
///     },
///     tools: .preset(.readOnly)
/// )
/// ```
public struct SubagentDefinition: Identifiable, Sendable {

    /// Unique identifier for the subagent.
    public let id: String

    /// The name of the subagent (used for invocation).
    public let name: String

    /// A description of what the subagent does.
    public let subagentDescription: String

    /// Instructions that define the subagent's behavior.
    public let instructions: Instructions

    /// Tools available to the subagent.
    public let tools: ToolConfiguration

    /// Model configuration override (uses parent's model if nil).
    public let modelConfiguration: ModelConfiguration?

    /// Model provider override (uses parent's model if nil).
    public let modelProvider: (any ModelProvider)?

    /// Maximum number of turns the subagent can take.
    public let maxTurns: Int

    /// Whether to inherit tools from the parent agent.
    public let inheritParentTools: Bool

    /// Creates a new subagent definition.
    ///
    /// - Parameters:
    ///   - name: The name of the subagent.
    ///   - description: A description of the subagent's purpose.
    ///   - instructions: Instructions that define behavior.
    ///   - tools: Tools available to the subagent.
    ///   - modelConfiguration: Optional model configuration override.
    ///   - modelProvider: Optional model provider override.
    ///   - maxTurns: Maximum turns (default: 10).
    ///   - inheritParentTools: Whether to inherit parent's tools (default: false).
    public init(
        name: String,
        description: String,
        instructions: Instructions,
        tools: ToolConfiguration = .preset(.default),
        modelConfiguration: ModelConfiguration? = nil,
        modelProvider: (any ModelProvider)? = nil,
        maxTurns: Int = 10,
        inheritParentTools: Bool = false
    ) {
        self.id = UUID().uuidString
        self.name = name
        self.subagentDescription = description
        self.instructions = instructions
        self.tools = tools
        self.modelConfiguration = modelConfiguration
        self.modelProvider = modelProvider
        self.maxTurns = maxTurns
        self.inheritParentTools = inheritParentTools
    }

    /// Creates a new subagent definition with a builder for instructions.
    ///
    /// - Parameters:
    ///   - name: The name of the subagent.
    ///   - description: A description of the subagent's purpose.
    ///   - tools: Tools available to the subagent.
    ///   - modelConfiguration: Optional model configuration override.
    ///   - modelProvider: Optional model provider override.
    ///   - maxTurns: Maximum turns (default: 10).
    ///   - inheritParentTools: Whether to inherit parent's tools.
    ///   - instructions: Instructions builder.
    public init(
        name: String,
        description: String,
        tools: ToolConfiguration = .preset(.default),
        modelConfiguration: ModelConfiguration? = nil,
        modelProvider: (any ModelProvider)? = nil,
        maxTurns: Int = 10,
        inheritParentTools: Bool = false,
        @InstructionsBuilder instructions: () throws -> Instructions
    ) rethrows {
        self.id = UUID().uuidString
        self.name = name
        self.subagentDescription = description
        self.instructions = try instructions()
        self.tools = tools
        self.modelConfiguration = modelConfiguration
        self.modelProvider = modelProvider
        self.maxTurns = maxTurns
        self.inheritParentTools = inheritParentTools
    }
}

// MARK: - Hashable

extension SubagentDefinition: Hashable {

    public func hash(into hasher: inout Hasher) {
        hasher.combine(id)
    }

    public static func == (lhs: SubagentDefinition, rhs: SubagentDefinition) -> Bool {
        lhs.id == rhs.id
    }
}

// MARK: - CustomStringConvertible

extension SubagentDefinition: CustomStringConvertible {

    public var description: String {
        "SubagentDefinition(name: \"\(name)\", description: \"\(subagentDescription)\", tools: \(tools))"
    }
}

// MARK: - Subagent Definition Builder

/// A result builder for creating subagent definitions.
@resultBuilder
public struct SubagentDefinitionBuilder {

    public static func buildBlock(_ definitions: SubagentDefinition...) -> [SubagentDefinition] {
        definitions
    }

    public static func buildOptional(_ definitions: [SubagentDefinition]?) -> [SubagentDefinition] {
        definitions ?? []
    }

    public static func buildEither(first definitions: [SubagentDefinition]) -> [SubagentDefinition] {
        definitions
    }

    public static func buildEither(second definitions: [SubagentDefinition]) -> [SubagentDefinition] {
        definitions
    }

    public static func buildArray(_ components: [[SubagentDefinition]]) -> [SubagentDefinition] {
        components.flatMap { $0 }
    }
}

// MARK: - Common Subagent Templates

extension SubagentDefinition {

    /// Creates a code reviewer subagent.
    ///
    /// - Parameter additionalInstructions: Additional instructions to append.
    /// - Returns: A configured code reviewer subagent.
    public static func codeReviewer(
        additionalInstructions: String? = nil
    ) -> SubagentDefinition {
        var instructionText = """
        You are an expert code reviewer. Your task is to review code and provide feedback on:
        - Bugs and potential issues
        - Performance improvements
        - Code readability and maintainability
        - Security vulnerabilities
        - Best practices and patterns

        Provide specific, actionable feedback with line references where applicable.
        """

        if let additional = additionalInstructions {
            instructionText += "\n\n\(additional)"
        }

        return SubagentDefinition(
            name: "code-reviewer",
            description: "Reviews code for issues, improvements, and best practices",
            instructions: Instructions(instructionText),
            tools: .preset(.readOnly)
        )
    }

    /// Creates a test writer subagent.
    ///
    /// - Parameter additionalInstructions: Additional instructions to append.
    /// - Returns: A configured test writer subagent.
    public static func testWriter(
        additionalInstructions: String? = nil
    ) -> SubagentDefinition {
        var instructionText = """
        You are an expert test writer. Your task is to write comprehensive tests that:
        - Cover edge cases and error conditions
        - Test both happy paths and failure scenarios
        - Use appropriate mocking and stubbing
        - Follow testing best practices
        - Are maintainable and readable

        Write tests that provide good coverage without being redundant.
        """

        if let additional = additionalInstructions {
            instructionText += "\n\n\(additional)"
        }

        return SubagentDefinition(
            name: "test-writer",
            description: "Writes comprehensive unit and integration tests",
            instructions: Instructions(instructionText),
            tools: .preset(.fileOnly)
        )
    }

    /// Creates a documentation writer subagent.
    ///
    /// - Parameter additionalInstructions: Additional instructions to append.
    /// - Returns: A configured documentation writer subagent.
    public static func documentationWriter(
        additionalInstructions: String? = nil
    ) -> SubagentDefinition {
        var instructionText = """
        You are an expert technical writer. Your task is to write clear documentation that:
        - Explains concepts clearly to the target audience
        - Includes practical examples
        - Covers common use cases
        - Documents edge cases and limitations
        - Uses consistent formatting and style

        Write documentation that helps developers understand and use the code effectively.
        """

        if let additional = additionalInstructions {
            instructionText += "\n\n\(additional)"
        }

        return SubagentDefinition(
            name: "documentation-writer",
            description: "Writes clear and comprehensive documentation",
            instructions: Instructions(instructionText),
            tools: .preset(.fileOnly)
        )
    }

    /// Creates a refactoring assistant subagent.
    ///
    /// - Parameter additionalInstructions: Additional instructions to append.
    /// - Returns: A configured refactoring assistant subagent.
    public static func refactoringAssistant(
        additionalInstructions: String? = nil
    ) -> SubagentDefinition {
        var instructionText = """
        You are an expert at code refactoring. Your task is to improve code by:
        - Extracting common patterns into reusable components
        - Simplifying complex logic
        - Improving naming and code organization
        - Applying appropriate design patterns
        - Maintaining backward compatibility when possible

        Make incremental, safe changes that preserve functionality while improving quality.
        """

        if let additional = additionalInstructions {
            instructionText += "\n\n\(additional)"
        }

        return SubagentDefinition(
            name: "refactoring-assistant",
            description: "Refactors code for better quality and maintainability",
            instructions: Instructions(instructionText),
            tools: .preset(.development)
        )
    }
}
