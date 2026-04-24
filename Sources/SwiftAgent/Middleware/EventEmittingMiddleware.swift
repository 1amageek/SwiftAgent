//
//  EventEmittingMiddleware.swift
//  SwiftAgent
//

import Foundation

/// Middleware that emits runtime tool lifecycle events to the `EventSink`
/// during tool execution.
///
/// This middleware provides real-time tool execution monitoring as a default
/// feature of `AgentSession`. It reads two TaskLocal contexts:
/// - `AgentSessionContext.current` — for `sessionID` and `turnID`
/// - `EventSinkContext.current` — for the event sink
///
/// When either context is unavailable (e.g., running outside `AgentSession`),
/// the middleware is a no-op and passes through to the next handler.
///
/// ## Event Flow
///
/// ```
/// .toolStarted(toolName, .running) ← emitted before tool execution
///     ↓
///   actual tool execution
///     ↓
/// .toolFinished(toolName, result)  ← emitted after tool execution
/// ```
///
/// ## Integration
///
/// Included in `ToolRuntimeConfiguration.default`. No manual configuration required.
///
/// ```swift
/// // Automatic: AgentSession sets AgentSessionContext + EventSinkContext,
/// // and the middleware emits events during tool execution.
/// let session = AgentSession(transport: transport)
/// try await session.run(conversation)
/// ```
public struct EventEmittingMiddleware: ToolMiddleware {

    public init() {}

    public func handle(_ context: ToolContext, next: @escaping Next) async throws -> ToolResult {
        guard let sessionContext = AgentSessionContext.current else {
            #if DEBUG
            print("[EventEmittingMiddleware] No AgentSessionContext — skipping for \(context.toolName)")
            #endif
            return try await next(context)
        }

        let sink = EventSinkContext.current
        let toolUseID = context.toolUseID ?? UUID().uuidString

        #if DEBUG
        print("[EventEmittingMiddleware] toolCall \(context.toolName) id=\(toolUseID)")
        #endif

        let started = RunEvent.ToolCallEvent(
            toolUseID: toolUseID,
            toolName: context.toolName,
            arguments: context.arguments,
            sessionID: sessionContext.sessionID,
            turnID: sessionContext.turnID
        )
        await sink.emit(.toolStarted(started))
        await sink.emit(.toolCall(started))

        let result: ToolResult
        do {
            result = try await next(context)
        } catch {
            let finished = RunEvent.ToolResultEvent(
                toolUseID: toolUseID,
                toolName: context.toolName,
                output: error.localizedDescription,
                success: false,
                duration: .zero,
                sessionID: sessionContext.sessionID,
                turnID: sessionContext.turnID
            )
            await sink.emit(.toolFinished(finished))
            await sink.emit(.toolResult(finished))
            throw error
        }

        #if DEBUG
        print("[EventEmittingMiddleware] toolResult \(context.toolName) success=\(result.success) duration=\(result.duration)")
        #endif

        let finished = RunEvent.ToolResultEvent(
            toolUseID: toolUseID,
            toolName: context.toolName,
            output: result.output,
            success: result.success,
            duration: result.duration,
            sessionID: sessionContext.sessionID,
            turnID: sessionContext.turnID
        )
        await sink.emit(.toolFinished(finished))
        await sink.emit(.toolResult(finished))

        return result
    }
}
