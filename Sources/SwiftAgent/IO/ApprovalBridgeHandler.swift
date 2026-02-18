//
//  ApprovalBridgeHandler.swift
//  SwiftAgent
//

import Foundation

/// Decorates an `ApprovalHandler` with event emission.
///
/// Emits `approvalRequired`/`approvalResolved` events around each
/// approval request, then delegates to the inner handler.
///
/// Created by `AgentSession` and injected via `ApprovalHandlerContext`.
final class ApprovalBridgeHandler: ApprovalHandler, @unchecked Sendable {
    private let inner: any ApprovalHandler
    private let eventSink: EventSink
    private let sessionID: String
    private let turnID: String

    init(
        inner: any ApprovalHandler,
        eventSink: EventSink,
        sessionID: String,
        turnID: String
    ) {
        self.inner = inner
        self.eventSink = eventSink
        self.sessionID = sessionID
        self.turnID = turnID
    }

    func requestApproval(
        _ request: PermissionRequest,
        approvalID: String
    ) async throws -> PermissionResponse {
        // 1. Emit approval_required
        await eventSink.emit(.approvalRequired(RunEvent.ApprovalRequestEvent(
            approvalID: approvalID,
            toolName: request.toolName,
            arguments: request.toolInput.description,
            operationDescription: request.operationDescription,
            riskLevel: request.riskLevel.rawValue,
            sessionID: sessionID,
            turnID: turnID
        )))

        // 2. Delegate to inner handler
        let response = try await inner.requestApproval(request, approvalID: approvalID)

        // 3. Emit approval_resolved
        let approvalDecision: ApprovalDecision = switch response {
        case .allowOnce: .allowOnce
        case .alwaysAllow: .alwaysAllow
        case .deny: .deny
        case .denyAndBlock: .denyAndBlock
        }
        await eventSink.emit(.approvalResolved(RunEvent.ApprovalResolvedEvent(
            approvalID: approvalID,
            decision: approvalDecision,
            sessionID: sessionID,
            turnID: turnID
        )))

        return response
    }
}
