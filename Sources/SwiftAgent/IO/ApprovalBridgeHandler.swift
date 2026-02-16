//
//  ApprovalBridgeHandler.swift
//  SwiftAgent
//

import Foundation

/// Bridges `PermissionMiddleware`'s `.ask` flow with the event system.
///
/// Implements `PermissionHandler` so it can be injected via
/// `PermissionHandlerContext`. Internally it emits
/// `approvalRequired`/`approvalResolved` events and delegates
/// to the transport-agnostic `ApprovalHandler`.
///
/// Created by `AgentRuntime` and injected via `PermissionHandlerContext`.
final class ApprovalBridgeHandler: PermissionHandler, @unchecked Sendable {
    private let approvalHandler: any ApprovalHandler
    private let eventSink: EventSink
    private let sessionID: String
    private let turnID: String

    init(
        approvalHandler: any ApprovalHandler,
        eventSink: EventSink,
        sessionID: String,
        turnID: String
    ) {
        self.approvalHandler = approvalHandler
        self.eventSink = eventSink
        self.sessionID = sessionID
        self.turnID = turnID
    }

    func requestPermission(_ request: PermissionRequest) async throws -> PermissionResponse {
        let approvalID = UUID().uuidString

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

        // 2. Delegate to transport-specific handler
        let response = try await approvalHandler.requestApproval(request, approvalID: approvalID)

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
