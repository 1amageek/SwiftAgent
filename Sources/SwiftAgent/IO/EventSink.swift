//
//  EventSink.swift
//  SwiftAgent
//

import Foundation
import Synchronization

/// A transport-agnostic sink for `RunEvent` emission.
///
/// `EventSink` is propagated via `@Context` to all Steps within an Agent run.
/// Steps and middleware emit events to this sink; the transport adapter
/// consumes them (e.g., writes to stdout, sends over SSE, etc.).
///
/// This replaces direct `print()` calls in `onStream` handlers.
///
/// ## Usage
///
/// ```swift
/// struct MyStep: Step {
///     @Context var events: EventSink
///
///     func run(_ input: String) async throws -> String {
///         await events.emit(.tokenDelta(RunEvent.TokenDelta(
///             delta: "Hello",
///             accumulated: "Hello",
///             isComplete: false
///         )))
///         return "Hello"
///     }
/// }
/// ```
public final class EventSink: @unchecked Sendable {

    private let _continuation: AsyncStream<RunEvent>.Continuation?
    private let handler: @Sendable (RunEvent) async -> Void
    private let state: Mutex<State>

    private struct State {
        var isFinished = false
        var hasTextualStream = false
    }

    /// Creates an EventSink backed by an AsyncStream continuation.
    ///
    /// Events emitted to this sink are yielded to the stream, which can
    /// be consumed by the transport adapter.
    public init(continuation: AsyncStream<RunEvent>.Continuation) {
        self._continuation = continuation
        self.state = Mutex(State())
        self.handler = { event in
            continuation.yield(event)
        }
    }

    /// Creates an EventSink backed by a closure.
    public init(handler: @escaping @Sendable (RunEvent) async -> Void) {
        self._continuation = nil
        self.state = Mutex(State())
        self.handler = handler
    }

    /// A null sink that discards all events.
    public static let null = EventSink { _ in }

    /// Emits an event to the sink. No-op after `finish()` has been called.
    public func emit(_ event: RunEvent) async {
        let finished = state.withLock { state -> Bool in
            if case .tokenDelta = event {
                state.hasTextualStream = true
            }
            if case .reasoningDelta = event {
                state.hasTextualStream = true
            }
            return state.isFinished
        }
        guard !finished else { return }
        await handler(event)
    }

    /// Emits a token delta event.
    ///
    /// Convenience for the most common streaming pattern.
    public func emitTokenDelta(delta: String, accumulated: String, isComplete: Bool = false) async {
        await emit(.tokenDelta(RunEvent.TokenDelta(
            delta: delta,
            accumulated: accumulated,
            isComplete: isComplete
        )))
    }

    /// Emits a reasoning delta event.
    public func emitReasoningDelta(delta: String, accumulated: String, isComplete: Bool = false) async {
        await emit(.reasoningDelta(RunEvent.TokenDelta(
            delta: delta,
            accumulated: accumulated,
            isComplete: isComplete
        )))
    }

    /// Returns whether any answer/reasoning stream event has been emitted.
    public var hasTextualStream: Bool {
        state.withLock(\.hasTextualStream)
    }

    /// Signals that the event stream for this turn is finished.
    public func finish() {
        state.withLock { $0.isFinished = true }
        _continuation?.finish()
    }
}

// MARK: - Contextable Conformance (manual)

/// ContextKey for EventSink, enabling `@Context var events: EventSink`.
public enum EventSinkContext: ContextKey {
    @TaskLocal private static var _current: EventSink?

    public static var defaultValue: EventSink { .null }

    public static var current: EventSink { _current ?? defaultValue }

    public static func withValue<T: Sendable>(
        _ value: EventSink,
        operation: () async throws -> T
    ) async rethrows -> T {
        try await $_current.withValue(value, operation: operation)
    }
}

extension EventSink: Contextable {
    public static var defaultValue: EventSink { .null }
    public typealias ContextKeyType = EventSinkContext
}
