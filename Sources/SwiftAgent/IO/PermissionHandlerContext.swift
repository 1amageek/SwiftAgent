//
//  PermissionHandlerContext.swift
//  SwiftAgent
//

import Foundation

/// TaskLocal context for injecting an `ApprovalHandler` into
/// `PermissionMiddleware`'s execution scope.
///
/// `AgentSession` wraps turn execution in
/// `ApprovalHandlerContext.withValue(handler)`. `PermissionMiddleware`
/// checks this context first when it needs to prompt for approval.
///
/// When `ApprovalHandlerContext.current` is `nil` (the default),
/// `PermissionMiddleware` falls back to its configured handler,
/// preserving full backward compatibility.
public enum ApprovalHandlerContext: ContextKey {
    @TaskLocal
    private static var _current: (any ApprovalHandler)?

    public static var defaultValue: (any ApprovalHandler)? { nil }

    public static var current: (any ApprovalHandler)? { _current }

    public static func withValue<T: Sendable>(
        _ value: (any ApprovalHandler)?,
        operation: () async throws -> T
    ) async rethrows -> T {
        try await $_current.withValue(value, operation: operation)
    }
}
