import Foundation
import Testing
@testable import SwiftAgent

@Suite("ConnectionApprovalHandler")
struct ConnectionApprovalHandlerTests {
    private let request = PermissionRequest(
        toolName: "Read",
        toolInput: ["path": "/tmp/input"]
    )

    @Test("Unknown approval IDs are observable")
    func unknownApprovalIDIsObservable() {
        let handler = ConnectionApprovalHandler()

        #expect(!handler.resolve(
            approvalID: "missing",
            decision: .allowOnce
        ))
    }

    @Test("Cancelling a waiter releases its approval ID", .timeLimit(.minutes(1)))
    func cancellationReleasesApprovalID() async throws {
        let handler = ConnectionApprovalHandler()
        let cancelled = Task {
            try await handler.requestApproval(request, approvalID: "approval")
        }
        await Task.yield()
        cancelled.cancel()

        await #expect(throws: CancellationError.self) {
            try await cancelled.value
        }

        let replacement = Task {
            try await handler.requestApproval(request, approvalID: "approval")
        }
        var didResolve = false
        for _ in 0..<100 where !didResolve {
            didResolve = handler.resolve(
                approvalID: "approval",
                decision: .allowOnce
            )
            if !didResolve {
                await Task.yield()
            }
        }

        #expect(didResolve)
        guard didResolve else {
            replacement.cancel()
            return
        }
        let response = try await replacement.value
        if case .allowOnce = response {
            // Expected.
        } else {
            Issue.record("Replacement approval returned the wrong decision")
        }
    }
}
