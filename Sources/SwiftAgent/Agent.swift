//
//  Agent.swift
//  SwiftAgent
//
//  Created by Norikazu Muramoto on 2025/01/12.
//

import Foundation

/// A protocol representing an interactive AI agent that processes inputs and produces outputs.
///
/// `Agent` extends `Step` with additional capabilities for managing tools, instructions,
/// and bidirectional communication through an AgentSession.
///
/// ## Overview
///
/// Agents are long-running entities that:
/// - Maintain an `AgentSession` for LLM interactions
/// - Define `tools` available to the LLM
/// - Define `instructions` that guide the LLM's behavior
/// - Process inputs from a queue and emit outputs to a stream
///
/// The `Output` type is `Never` because agents run indefinitely. Actual outputs are
/// emitted through the `outputs` continuation.
///
/// ## Usage
///
/// ```swift
/// struct EchoAgent: Agent {
///     let session: AgentSession
///     let outputs: AsyncStream<String>.Continuation
///
///     var instructions: Instructions {
///         Instructions("Echo everything back")
///     }
///
///     var body: some Step<AgentSession.Response, String> {
///         Transform { response in
///             "Echo: \(response.content)"
///         }
///     }
/// }
///
/// // Usage
/// let languageModelSession = LanguageModelSession(model: model) {
///     Instructions("Test")
/// }
/// let (stream, continuation) = AsyncStream<String>.makeStream()
/// let session = AgentSession(languageModelSession: languageModelSession)
/// let agent = EchoAgent(session: session, outputs: continuation)
///
/// // Run in background
/// Task {
///     try await agent.run("Hello")
/// }
///
/// // Add more inputs
/// session.input("World")
///
/// // Receive outputs
/// for await output in stream {
///     print(output)
/// }
/// ```
public protocol Agent: Step where Input == String, Output == Never {
    /// The tools available to this agent.
    var tools: [any Tool] { get }

    /// The instructions that guide the agent's behavior.
    @InstructionsBuilder
    var instructions: Instructions { get }

    /// The session managing the agent's conversation state.
    var session: AgentSession { get }

    /// The continuation for emitting outputs to consumers.
    var outputs: AsyncStream<String>.Continuation { get }
}

// MARK: - Agent Default Implementations

extension Agent {
    /// Default empty tools array.
    public var tools: [any Tool] { [] }
}

extension Agent where Body: Step,
                      Body.Input == AgentSession.Response,
                      Body.Output == String {

    /// Default run implementation that enters an infinite processing loop.
    ///
    /// This implementation:
    /// 1. Queues the initial input
    /// 2. Enters an infinite loop that:
    ///    - Waits for input from the queue
    ///    - Sends the input to the session
    ///    - Processes the response through the body
    ///    - Yields the output to the outputs stream
    ///
    /// The loop continues until the task is cancelled.
    ///
    /// - Parameter initial: The initial input to start the agent.
    /// - Returns: Never returns (runs indefinitely until cancelled).
    /// - Throws: `CancellationError` if the task is cancelled.
    public func run(_ initial: String) async throws -> Never {
        session.input(initial)
        while true {
            try Task.checkCancellation()
            let input = try await session.waitForInput()
            let response = try await session.send(input)
            let output = try await body.run(response)
            outputs.yield(output)
        }
    }
}
