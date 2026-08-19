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
public final class EventSink: Sendable {
    private let handler: @Sendable (RunEvent) async -> Void
    private let state: Mutex<State>

    private struct State: Sendable {
        var isFinished = false
        var hasTextualStream = false
        var deliveryTail: Task<Void, Never>?
        var finishTask: Task<Void, Never>?
    }

    /// Creates an EventSink backed by a closure.
    public init(handler: @escaping @Sendable (RunEvent) async -> Void) {
        self.state = Mutex(State())
        self.handler = handler
    }

    /// A null sink that discards all events.
    public static let null = EventSink { _ in }

    /// Emits an event to the sink. No-op after `finish()` has been called.
    public func emit(_ event: RunEvent) async {
        let handler = self.handler
        let delivery = state.withLock { state -> Task<Void, Never>? in
            guard !state.isFinished else {
                return nil
            }
            if case .tokenDelta = event {
                state.hasTextualStream = true
            }
            if case .reasoningDelta = event {
                state.hasTextualStream = true
            }
            let previous = state.deliveryTail
            let delivery = Task {
                await previous?.value
                await handler(event)
            }
            state.deliveryTail = delivery
            return delivery
        }
        await delivery?.value
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

    /// Rejects subsequent events and drains every delivery already accepted.
    public func finish() async {
        let finishTask = state.withLock { state -> Task<Void, Never> in
            if let finishTask = state.finishTask {
                return finishTask
            }
            state.isFinished = true
            let pendingDelivery = state.deliveryTail
            state.deliveryTail = nil
            let finishTask = Task<Void, Never> {
                if let pendingDelivery {
                    await pendingDelivery.value
                }
            }
            state.finishTask = finishTask
            return finishTask
        }
        await finishTask.value
    }
}
