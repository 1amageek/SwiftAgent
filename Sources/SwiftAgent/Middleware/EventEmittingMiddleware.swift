//
//  EventEmittingMiddleware.swift
//  SwiftAgent
//

import Foundation

/// Middleware that emits `RunEvent.toolCall` and `RunEvent.toolResult` events
/// to the `EventSink` during tool execution.
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
/// .toolCall(toolName, .running)   ← emitted before tool execution
///     ↓
///   actual tool execution
///     ↓
/// .toolResult(toolName, result)   ← emitted after tool execution
/// ```
///
/// ## Integration
///
/// Included in `ToolPipeline.default`. No manual configuration required.
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

        await sink.emit(.toolCall(RunEvent.ToolCallEvent(
            toolUseID: toolUseID,
            toolName: context.toolName,
            arguments: context.arguments,
            sessionID: sessionContext.sessionID,
            turnID: sessionContext.turnID
        )))

        let result: ToolResult
        do {
            result = try await next(context)
        } catch {
            await sink.emit(.toolResult(RunEvent.ToolResultEvent(
                toolUseID: toolUseID,
                toolName: context.toolName,
                output: error.localizedDescription,
                success: false,
                duration: .zero,
                sessionID: sessionContext.sessionID,
                turnID: sessionContext.turnID
            )))
            throw error
        }

        #if DEBUG
        print("[EventEmittingMiddleware] toolResult \(context.toolName) success=\(result.success) duration=\(result.duration)")
        #endif

        await sink.emit(.toolResult(RunEvent.ToolResultEvent(
            toolUseID: toolUseID,
            toolName: context.toolName,
            output: result.output,
            success: result.success,
            duration: result.duration,
            sessionID: sessionContext.sessionID,
            turnID: sessionContext.turnID
        )))

        return result
    }
}
