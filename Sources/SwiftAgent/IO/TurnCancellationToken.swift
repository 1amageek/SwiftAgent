//
//  TurnCancellationToken.swift
//  SwiftAgent
//

import Foundation
import Synchronization

/// A cooperative cancellation token for turn-level cancellation.
///
/// Unlike `Task.cancel()`, which requires Sendable conformance on the agent,
/// `TurnCancellationToken` uses a shared flag that can be set from the receive loop
/// and checked at various checkpoints within the turn execution.
///
/// ## Usage
///
/// ```swift
/// let token = TurnCancellationToken()
///
/// // From receive loop (on .cancel):
/// token.cancel()
///
/// // From within turn execution:
/// try token.checkCancellation()  // throws CancellationError if cancelled
/// ```
public final class TurnCancellationToken: Sendable {
    private let _isCancelled: Mutex<Bool> = Mutex(false)

    public init() {}

    /// Whether cancellation has been requested.
    public var isCancelled: Bool {
        _isCancelled.withLock { $0 }
    }

    /// Throws `CancellationError` if cancellation has been requested.
    public func checkCancellation() throws {
        if isCancelled {
            throw CancellationError()
        }
    }

    /// Requests cancellation. Thread-safe; can be called from any context.
    public func cancel() {
        _isCancelled.withLock { $0 = true }
    }
}

/// TaskLocal context for propagating the active turn's cancellation token.
///
/// Follows the same pattern as `EventSinkContext` and `PermissionHandlerContext`.
public enum TurnCancellationContext: ContextKey {
    @TaskLocal private static var _current: TurnCancellationToken?

    public static var defaultValue: TurnCancellationToken? { nil }

    public static var current: TurnCancellationToken? { _current }

    public static func withValue<T: Sendable>(
        _ value: TurnCancellationToken?,
        operation: () async throws -> T
    ) async rethrows -> T {
        try await $_current.withValue(value, operation: operation)
    }
}
