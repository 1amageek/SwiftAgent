import Foundation
import Synchronization

/// Resolves approval requests from correlated Agent connection responses.
public final class ConnectionApprovalHandler: ApprovalHandler, Sendable {
    private struct PendingApproval: Sendable {
        let registrationID: UUID
        let continuation: CheckedContinuation<PermissionResponse, any Error>
    }

    private enum Registration {
        case stored
        case cancelled
        case duplicate
    }

    private let pendingApprovals = Mutex<[String: PendingApproval]>([:])

    public init() {}

    public func requestApproval(
        _ request: PermissionRequest,
        approvalID: String
    ) async throws -> PermissionResponse {
        let registrationID = UUID()
        return try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { continuation in
                let registration = pendingApprovals.withLock {
                    pending -> Registration in
                    if Task.isCancelled {
                        return .cancelled
                    }
                    guard pending[approvalID] == nil else {
                        return .duplicate
                    }
                    pending[approvalID] = PendingApproval(
                        registrationID: registrationID,
                        continuation: continuation
                    )
                    return .stored
                }
                switch registration {
                case .stored:
                    break
                case .cancelled:
                    continuation.resume(throwing: CancellationError())
                case .duplicate:
                    continuation.resume(throwing: AgentConnectionError.invalidState(
                        "Duplicate pending approval ID '\(approvalID)'"
                    ))
                }
            }
        } onCancel: {
            cancel(approvalID: approvalID, registrationID: registrationID)
        }
    }

    @discardableResult
    public func resolve(
        approvalID: String,
        decision: PermissionResponse
    ) -> Bool {
        let pendingApproval = pendingApprovals.withLock { pending in
            pending.removeValue(forKey: approvalID)
        }
        pendingApproval?.continuation.resume(returning: decision)
        return pendingApproval != nil
    }

    public func rejectAll(error: any Error) {
        let approvals = pendingApprovals.withLock { pending in
            let approvals = Array(pending.values)
            pending.removeAll()
            return approvals
        }
        for approval in approvals {
            approval.continuation.resume(throwing: error)
        }
    }

    private func cancel(approvalID: String, registrationID: UUID) {
        let pendingApproval = pendingApprovals.withLock {
            pending -> PendingApproval? in
            guard pending[approvalID]?.registrationID == registrationID else {
                return nil
            }
            return pending.removeValue(forKey: approvalID)
        }
        pendingApproval?.continuation.resume(throwing: CancellationError())
    }
}
