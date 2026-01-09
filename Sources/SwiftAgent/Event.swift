//
//  Event.swift
//  SwiftAgent
//
//  Created by SwiftAgent on 2025/01/09.
//

import Foundation

// MARK: - EventName

/// A type-safe event name, similar to `Notification.Name`.
///
/// Define your event names as static properties in an extension:
///
/// ```swift
/// extension EventName {
///     static let sessionStarted = EventName("sessionStarted")
///     static let sessionEnded = EventName("sessionEnded")
/// }
/// ```
public struct EventName: RawRepresentable, Hashable, Sendable {
    public let rawValue: String

    public init(rawValue: String) {
        self.rawValue = rawValue
    }

    public init(_ rawValue: String) {
        self.rawValue = rawValue
    }
}

// MARK: - EventTiming

/// When to emit an event relative to Step execution.
public enum EventTiming: Sendable {
    /// Emit before the Step runs.
    case before
    /// Emit after the Step completes.
    case after
}

// MARK: - EventBus

/// A context-propagated event bus for emitting and listening to events.
///
/// Use `@Context` to access the event bus from any Step:
///
/// ```swift
/// struct MyStep: Step {
///     @Context var events: EventBus
///
///     func run(_ input: String) async throws -> String {
///         await events.emit(.processingStarted)
///         // ...
///         return result
///     }
/// }
/// ```
///
/// Or use the `.emit()` modifier:
///
/// ```swift
/// MyStep()
///     .emit(.started, on: .before)
///     .emit(.completed, on: .after)
/// ```
@Contextable
public actor EventBus {

    /// Payload delivered to event handlers.
    public struct Payload: Sendable {
        /// The event name.
        public let name: EventName
        /// Optional value associated with the event.
        public let value: (any Sendable)?

        public init(name: EventName, value: (any Sendable)? = nil) {
            self.name = name
            self.value = value
        }
    }

    public typealias Handler = @Sendable (Payload) async -> Void

    private var listeners: [EventName: [Handler]] = [:]

    public static var defaultValue: EventBus { EventBus() }

    public init() {}

    /// Emits an event to all registered listeners.
    ///
    /// - Parameters:
    ///   - name: The event name.
    ///   - value: Optional value to include in the payload.
    public func emit(_ name: EventName, value: (any Sendable)? = nil) async {
        let handlers = listeners[name] ?? []
        let payload = Payload(name: name, value: value)
        for handler in handlers {
            await handler(payload)
        }
    }

    /// Registers a handler for an event.
    ///
    /// - Parameters:
    ///   - name: The event name to listen for.
    ///   - handler: The handler to call when the event is emitted.
    public func on(_ name: EventName, handler: @escaping Handler) {
        listeners[name, default: []].append(handler)
    }

    /// Removes all handlers for an event.
    ///
    /// - Parameter name: The event name.
    public func off(_ name: EventName) {
        listeners[name] = nil
    }

    /// Removes all handlers for all events.
    public func removeAllHandlers() {
        listeners.removeAll()
    }
}

// MARK: - EmittingStep

/// A Step wrapper that emits events before and/or after execution.
public struct EmittingStep<Base: Step>: Step {
    public typealias Input = Base.Input
    public typealias Output = Base.Output

    private let base: Base
    private let beforeEvents: [(EventName, ((any Sendable)?) -> (any Sendable)?)]
    private let afterEvents: [(EventName, (Output) -> (any Sendable)?)]

    init(
        base: Base,
        beforeEvents: [(EventName, ((any Sendable)?) -> (any Sendable)?)] = [],
        afterEvents: [(EventName, (Output) -> (any Sendable)?)] = []
    ) {
        self.base = base
        self.beforeEvents = beforeEvents
        self.afterEvents = afterEvents
    }

    public func run(_ input: Input) async throws -> Output {
        // Get EventBus from context
        let eventBus = EventBusContext.current

        // Emit before events
        for (name, payload) in beforeEvents {
            await eventBus.emit(name, value: payload(nil))
        }

        // Run the base step
        let output = try await base.run(input)

        // Emit after events
        for (name, payload) in afterEvents {
            await eventBus.emit(name, value: payload(output))
        }

        return output
    }
}

// MARK: - Step Extension

extension Step {

    /// Emits an event before or after this Step executes.
    ///
    /// ```swift
    /// MyStep()
    ///     .emit(.started, on: .before)
    ///     .emit(.completed, on: .after)
    /// ```
    ///
    /// - Parameters:
    ///   - name: The event name to emit.
    ///   - timing: When to emit (`.before` or `.after`). Defaults to `.after`.
    /// - Returns: A Step that emits the event at the specified timing.
    public func emit(
        _ name: EventName,
        on timing: EventTiming = .after
    ) -> EmittingStep<Self> {
        switch timing {
        case .before:
            return EmittingStep(
                base: self,
                beforeEvents: [(name, { _ in nil })],
                afterEvents: []
            )
        case .after:
            return EmittingStep(
                base: self,
                beforeEvents: [],
                afterEvents: [(name, { _ in nil })]
            )
        }
    }

    /// Emits an event with a payload derived from the output.
    ///
    /// ```swift
    /// MyStep()
    ///     .emit(.completed) { output in
    ///         output.summary
    ///     }
    /// ```
    ///
    /// - Parameters:
    ///   - name: The event name to emit.
    ///   - timing: When to emit. Defaults to `.after`.
    ///   - payload: A closure that creates the payload from the output.
    /// - Returns: A Step that emits the event with the payload.
    public func emit<P: Sendable>(
        _ name: EventName,
        on timing: EventTiming = .after,
        payload: @escaping @Sendable (Output) -> P
    ) -> EmittingStep<Self> {
        switch timing {
        case .before:
            return EmittingStep(
                base: self,
                beforeEvents: [(name, { _ in nil })],
                afterEvents: []
            )
        case .after:
            return EmittingStep(
                base: self,
                beforeEvents: [],
                afterEvents: [(name, { payload($0) })]
            )
        }
    }
}

// MARK: - EmittingStep Chaining

extension EmittingStep {

    /// Adds another event emission to this Step.
    public func emit(
        _ name: EventName,
        on timing: EventTiming = .after
    ) -> EmittingStep<Base> {
        switch timing {
        case .before:
            return EmittingStep(
                base: base,
                beforeEvents: beforeEvents + [(name, { _ in nil })],
                afterEvents: afterEvents
            )
        case .after:
            return EmittingStep(
                base: base,
                beforeEvents: beforeEvents,
                afterEvents: afterEvents + [(name, { _ in nil })]
            )
        }
    }

    /// Adds another event emission with payload to this Step.
    public func emit<P: Sendable>(
        _ name: EventName,
        on timing: EventTiming = .after,
        payload: @escaping @Sendable (Output) -> P
    ) -> EmittingStep<Base> {
        switch timing {
        case .before:
            return EmittingStep(
                base: base,
                beforeEvents: beforeEvents + [(name, { _ in nil })],
                afterEvents: afterEvents
            )
        case .after:
            return EmittingStep(
                base: base,
                beforeEvents: beforeEvents,
                afterEvents: afterEvents + [(name, { payload($0) })]
            )
        }
    }
}
