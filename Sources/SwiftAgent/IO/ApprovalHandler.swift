//
//  ApprovalHandler.swift
//  SwiftAgent
//

import Foundation
import Synchronization

/// A transport-agnostic handler for tool approval requests.
///
/// `ApprovalHandler` uses correlation IDs and integrates with the event system,
/// enabling approval flows over any transport (CLI, HTTP+SSE, WebSocket).
///
/// Built-in implementations: `CLIPermissionHandler`, `AlwaysAllowHandler`,
/// `AlwaysDenyHandler`, `ClosurePermissionHandler`, `AutoDenyApprovalHandler`,
/// `TransportApprovalHandler`.
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

// MARK: - AutoDenyApprovalHandler

/// Handler that auto-denies all approval requests.
///
/// Used when the transport cannot handle interactive approval
/// (e.g., batch processing, headless server).
///
/// Per SPEC: "transport が承認不能なら明示的に denied として終了"
public struct AutoDenyApprovalHandler: ApprovalHandler {
    public init() {}

    public func requestApproval(
        _ request: PermissionRequest,
        approvalID: String
    ) async throws -> PermissionResponse {
        .deny
    }
}

// MARK: - TransportApprovalHandler

/// A permission handler that routes approval requests through the transport layer.
///
/// Instead of calling `readLine()` directly, it:
/// 1. Emits an `approvalRequired` event via `EventSink`
/// 2. Suspends until the transport delivers an `ApprovalResponse`
/// 3. Returns the response as a `PermissionResponse`
///
/// This enables approval flows over HTTP+SSE, WebSocket, or any transport.
public final class TransportApprovalHandler: ApprovalHandler, @unchecked Sendable {

    private let pendingApprovals: Mutex<[String: CheckedContinuation<PermissionResponse, any Error>]>

    public init() {
        self.pendingApprovals = Mutex([:])
    }

    public func requestApproval(
        _ request: PermissionRequest,
        approvalID: String
    ) async throws -> PermissionResponse {
        try await withCheckedThrowingContinuation { continuation in
            pendingApprovals.withLock { $0[approvalID] = continuation }
        }
    }

    /// Resolves a pending approval.
    ///
    /// Called by `AgentSession` when it receives an `ApprovalResponse` from the transport.
    public func resolve(approvalID: String, decision: PermissionResponse) {
        let continuation = pendingApprovals.withLock { pending -> CheckedContinuation<PermissionResponse, any Error>? in
            pending.removeValue(forKey: approvalID)
        }
        continuation?.resume(returning: decision)
    }

    /// Rejects all pending approvals (e.g., on timeout or transport close).
    public func rejectAll(error: any Error) {
        let continuations = pendingApprovals.withLock { pending -> [CheckedContinuation<PermissionResponse, any Error>] in
            let values = Array(pending.values)
            pending.removeAll()
            return values
        }
        for continuation in continuations {
            continuation.resume(throwing: error)
        }
    }
}
