//
//  Agent.swift
//  SwiftAgent
//
//  Created by Norikazu Muramoto on 2025/01/12.
//

import Foundation

/// A protocol representing an AI agent that processes a single turn of input and produces a result.
///
/// `Agent` extends `Step` with additional capabilities for managing tools and instructions.
/// Each invocation of `run(_:)` processes exactly one turn (one `RunRequest` → one `RunResult`).
/// The infinite loop for interactive sessions is managed by `AgentRuntime`.
///
/// ## Overview
///
/// Agents:
/// - Define `tools` available to the LLM
/// - Define `instructions` that guide the LLM's behavior
/// - Use `@Session` to access the injected `LanguageModelSession`
/// - Process a `RunRequest` and return a `RunResult`
///
/// ## Usage
///
/// ```swift
/// struct ChatAgent: Agent {
///     @Session var session: LanguageModelSession
///
///     var instructions: Instructions {
///         Instructions("You are a helpful assistant")
///     }
///
///     var body: some Step<String, String> {
///         GenerateText(session: session) { Prompt($0) }
///     }
/// }
///
/// // Single turn
/// let request = RunRequest(input: .text("Hello"))
/// let result = try await ChatAgent()
///     .session(mySession)
///     .run(request)
///
/// // Multi-turn via runtime
/// let runtime = AgentRuntime(transport: myTransport, approvalHandler: myHandler)
/// try await runtime.run(agent: ChatAgent(), session: mySession)
/// ```
public protocol Agent: Step where Input == RunRequest, Output == RunResult {
    /// The tools available to this agent.
    var tools: [any Tool] { get }

    /// The instructions that guide the agent's behavior.
    @InstructionsBuilder
    var instructions: Instructions { get }
}

// MARK: - Agent Default Implementations

extension Agent {
    /// Default empty tools array.
    public var tools: [any Tool] { [] }
}

extension Agent where Body: Step,
                      Body.Input == String,
                      Body.Output == String {

    /// Default run implementation that processes a single turn.
    ///
    /// This implementation:
    /// 1. Extracts the text input from the `RunRequest`
    /// 2. Applies steering from the request context
    /// 3. Runs the text through the `body`
    /// 4. Wraps the result in a `RunResult`
    ///
    /// Non-text inputs (approvalResponse, cancel) return appropriate error results.
    ///
    /// - Parameter request: The run request to process.
    /// - Returns: The result of the run.
    public func run(_ request: RunRequest) async throws -> RunResult {
        let startTime = ContinuousClock.now

        guard case .text(let text) = request.input else {
            let duration = ContinuousClock.now - startTime
            return RunResult(
                sessionID: request.sessionID,
                turnID: request.turnID,
                status: .failed,
                error: RunEvent.RunError(
                    message: "Agent expected text input but received \(request.input)",
                    sessionID: request.sessionID,
                    turnID: request.turnID
                ),
                duration: duration
            )
        }

        let eventSink = EventSinkContext.current

        // Emit run started
        await eventSink.emit(.runStarted(RunEvent.RunStarted(
            sessionID: request.sessionID,
            turnID: request.turnID
        )))

        do {
            // Build input with steering
            let input = buildInput(text: text, context: request.context)

            // Check for turn-level cancellation before processing
            try TurnCancellationContext.current?.checkCancellation()

            // Process through body
            let output = try await body.run(input)
            let duration = ContinuousClock.now - startTime

            // Emit run completed
            await eventSink.emit(.runCompleted(RunEvent.RunCompleted(
                sessionID: request.sessionID,
                turnID: request.turnID,
                status: .completed
            )))

            return RunResult(
                sessionID: request.sessionID,
                turnID: request.turnID,
                status: .completed,
                finalOutput: output,
                duration: duration
            )

        } catch is CancellationError {
            let duration = ContinuousClock.now - startTime
            await eventSink.emit(.runCompleted(RunEvent.RunCompleted(
                sessionID: request.sessionID,
                turnID: request.turnID,
                status: .cancelled
            )))
            return RunResult(
                sessionID: request.sessionID,
                turnID: request.turnID,
                status: .cancelled,
                duration: duration
            )

        } catch {
            let duration = ContinuousClock.now - startTime
            let runError = RunEvent.RunError(
                message: error.localizedDescription,
                isFatal: true,
                underlyingError: error,
                sessionID: request.sessionID,
                turnID: request.turnID
            )
            await eventSink.emit(.error(runError))
            await eventSink.emit(.runCompleted(RunEvent.RunCompleted(
                sessionID: request.sessionID,
                turnID: request.turnID,
                status: .failed
            )))
            return RunResult(
                sessionID: request.sessionID,
                turnID: request.turnID,
                status: .failed,
                error: runError,
                duration: duration
            )
        }
    }

    /// Builds the input text by combining the main text with steering messages.
    private func buildInput(text: String, context: ContextPayload?) -> String {
        guard let steering = context?.steering, !steering.isEmpty else {
            return text
        }
        return ([text] + steering).joined(separator: "\n\n")
    }
}
