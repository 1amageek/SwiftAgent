//
//  Agent.swift
//  SwiftAgent
//
//  Created by Norikazu Muramoto on 2025/01/12.
//

import Foundation

/// A protocol representing an AI agent that defines tools, instructions, and a processing body.
///
/// `Agent` is a declarative protocol for defining agent behavior. The actual execution
/// is handled by `Conversation` (single turn) or `AgentSession` (multi-turn loop).
///
/// ## Overview
///
/// Agents:
/// - Define `tools` available to the LLM
/// - Define `instructions` that guide the LLM's behavior
/// - Define a `body` Step that processes `String -> String`
///
/// ## Usage
///
/// ```swift
/// struct ChatAgent: Agent {
///     var instructions: Instructions {
///         Instructions("You are a helpful assistant")
///     }
///
///     var body: some Step<String, String> {
///         GenerateText(session: session) { Prompt($0) }
///     }
/// }
/// ```
public protocol Agent {
    associatedtype Body: Step where Body.Input == String, Body.Output == String

    /// The tools available to this agent.
    var tools: [any Tool] { get }

    /// The instructions that guide the agent's behavior.
    @InstructionsBuilder
    var instructions: Instructions { get }

    /// The processing pipeline for this agent.
    @StepBuilder
    var body: Body { get }
}

// MARK: - Agent Default Implementations

extension Agent {
    /// Default empty tools array.
    public var tools: [any Tool] { [] }
}
