//
//  PermissionHandlerContext.swift
//  SwiftAgent
//

import Foundation

/// TaskLocal context for injecting a `PermissionHandler` into
/// `PermissionMiddleware`'s execution scope.
///
/// `AgentRuntime` wraps turn execution in
/// `PermissionHandlerContext.withValue(handler)`. `PermissionMiddleware`
/// checks this context first when it needs to prompt for approval.
///
/// When `PermissionHandlerContext.current` is `nil` (the default),
/// `PermissionMiddleware` falls back to its configured handler,
/// preserving full backward compatibility.
public enum PermissionHandlerContext: ContextKey {
    @TaskLocal
    private static var _current: (any PermissionHandler)?

    public static var defaultValue: (any PermissionHandler)? { nil }

    public static var current: (any PermissionHandler)? { _current }

    public static func withValue<T: Sendable>(
        _ value: (any PermissionHandler)?,
        operation: () async throws -> T
    ) async rethrows -> T {
        try await $_current.withValue(value, operation: operation)
    }
}
