/// Denies every approval request for non-interactive execution.
public struct AutoDenyApprovalHandler: ApprovalHandler {
    public init() {}

    public func requestApproval(
        _ request: PermissionRequest,
        approvalID: String
    ) async throws -> PermissionResponse {
        .deny
    }
}
