//
//  ApprovalHandler.swift
//  SwiftAgent
//

/// A transport-agnostic handler for tool approval requests.
///
/// `ApprovalHandler` uses correlation IDs and integrates with the event system,
/// enabling approval flows over any concrete Agent connection.
///
/// Built-in implementations: `CLIPermissionHandler`, `AlwaysAllowHandler`,
/// `AlwaysDenyHandler`, `ClosurePermissionHandler`, `AutoDenyApprovalHandler`,
/// `ConnectionApprovalHandler`.
///
/// ## Lifecycle
///
/// ```
/// PermissionMiddleware detects .ask decision
///     → generates approvalID
///     → calls handler.requestApproval(request, approvalID)
///     → continues or denies based on response
/// ```
public protocol ApprovalHandler: Sendable {
    /// Requests approval for a tool invocation.
    ///
    /// - Parameters:
    ///   - request: The approval request with full context.
    ///   - approvalID: Correlation ID for matching with events.
    /// - Returns: The user's decision.
    func requestApproval(
        _ request: PermissionRequest,
        approvalID: String
    ) async throws -> PermissionResponse
}

/// An approval handler that is safe while a non-concurrent request source is
/// paused for the active turn.
///
/// Conforming handlers must not open a second reader for the connection's
/// underlying input resource. A connection-specific handler may instead route
/// approval input through the same connection owner.
public protocol TurnGatedApprovalHandler: ApprovalHandler {}
