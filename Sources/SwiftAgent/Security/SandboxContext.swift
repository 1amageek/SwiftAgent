//
//  SandboxContext.swift
//  SwiftAgent
//
//  Created by SwiftAgent on 2025/01/04.
//

import Foundation

/// Context key for sandbox configuration propagation via TaskLocal.
public enum SandboxContext: ContextKey {
    @TaskLocal
    private static var _current: SandboxExecutor.Configuration?

    public static var defaultValue: SandboxExecutor.Configuration {
        .none
    }

    public static var current: SandboxExecutor.Configuration {
        _current ?? defaultValue
    }

    public static func withValue<T: Sendable>(
        _ value: SandboxExecutor.Configuration,
        operation: () async throws -> T
    ) async rethrows -> T {
        try await $_current.withValue(value, operation: operation)
    }
}

// MARK: - Contextable Conformance

extension SandboxExecutor.Configuration: Contextable {
    public static var defaultValue: SandboxExecutor.Configuration { .none }
    public typealias ContextKeyType = SandboxContext
}
