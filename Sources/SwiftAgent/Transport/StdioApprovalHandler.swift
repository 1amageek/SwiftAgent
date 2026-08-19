/// Routes interactive approval through the `StdioConnection` that already
/// owns stdin, preserving a single reader for the physical input resource.
public struct StdioApprovalHandler: TurnGatedApprovalHandler {
    private let connection: StdioConnection

    public init(connection: StdioConnection) {
        self.connection = connection
    }

    public func requestApproval(
        _ request: PermissionRequest,
        approvalID: String
    ) async throws -> PermissionResponse {
        try await connection.requestApproval(
            request,
            approvalID: approvalID
        )
    }
}
