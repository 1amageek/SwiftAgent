//
//  Event.swift
//  SwiftAgent
//
//  Created by SwiftAgent on 2025/01/09.
//

import Foundation
import Synchronization

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

// MARK: - Standard Event Names

extension EventName {
    /// Emitted when a prompt is submitted to an Conversation.
    public static let promptSubmitted = EventName("promptSubmitted")

    /// Emitted when a response is completed by an Conversation.
    public static let responseCompleted = EventName("responseCompleted")

    /// Emitted for notifications, warnings, or errors that don't interrupt processing.
    /// Value typically contains a descriptive message string.
    public static let notification = EventName("notification")
}

// MARK: - EventTiming

/// When to emit an event relative to Step execution.
public enum EventTiming: Sendable {
    /// Emit before the Step runs.
    case before
    /// Emit after the Step completes.
    case after
}

// MARK: - Event Protocol

/// A type-safe event that can be emitted through EventBus.
///
/// Implement this protocol to create custom event types:
///
/// ```swift
/// struct MyCustomEvent: Event {
///     let name: EventName
///     let timestamp: Date
///     let customProperty: String
/// }
/// ```
public protocol Event: Sendable {
    /// The event name.
    var name: EventName { get }
    /// When the event was created.
    var timestamp: Date { get }
}

// MARK: - SessionEvent

/// An event emitted by Conversation.
///
/// Use this for session lifecycle events like prompt submission and response completion.
public struct SessionEvent: Event {
    public let name: EventName
    public let timestamp: Date
    public let sessionID: String
    public let value: (any Sendable)?

    public init(
        name: EventName,
        sessionID: String,
        value: (any Sendable)? = nil,
        timestamp: Date = Date()
    ) {
        self.name = name
        self.timestamp = timestamp
        self.sessionID = sessionID
        self.value = value
    }
}

// MARK: - StepEvent

/// An event emitted by Step execution.
///
/// Use this for Step lifecycle events like step started and completed.
public struct StepEvent: Event {
    public let name: EventName
    public let timestamp: Date
    public let stepName: String
    public let value: (any Sendable)?

    public init(
        name: EventName,
        stepName: String,
        value: (any Sendable)? = nil,
        timestamp: Date = Date()
    ) {
        self.name = name
        self.timestamp = timestamp
        self.stepName = stepName
        self.value = value
    }
}

// MARK: - CommunityEvent

/// An event emitted by distributed agents (community coordination).
///
/// Use this for multi-agent coordination events.
///
/// Previously named `AgentEvent`. Renamed to `CommunityEvent` to avoid
/// collision with the `RunEvent` system used for Agent I/O.
public struct CommunityEvent: Event {
    public let name: EventName
    public let timestamp: Date
    public let agentID: String
    public let value: (any Sendable)?

    public init(
        name: EventName,
        agentID: String,
        value: (any Sendable)? = nil,
        timestamp: Date = Date()
    ) {
        self.name = name
        self.timestamp = timestamp
        self.agentID = agentID
        self.value = value
    }
}

/// Backward-compatible type alias.
@available(*, deprecated, renamed: "CommunityEvent")
public typealias AgentEvent = CommunityEvent

// MARK: - EventBus

/// A thread-safe event bus for emitting and listening to events.
///
/// EventBus is a class (not actor) using Mutex for thread safety,
/// making it compatible with distributed actors and other contexts
/// where actor isolation is problematic.
///
/// Use `@Context` to access the event bus from any Step:
///
/// ```swift
/// struct MyStep: Step {
///     @Context var events: EventBus
///
///     func run(_ input: String) async throws -> String {
///         await events.emit(StepEvent(name: .processingStarted, stepName: "MyStep"))
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
public final class EventBus: Sendable {

    public typealias Handler = @Sendable (any Event) async -> Void

    private let handlers: Mutex<[EventName: [Handler]]>

    public static var defaultValue: EventBus { EventBus() }

    public init() {
        self.handlers = Mutex([:])
    }

    /// Emits an event to all registered listeners.
    ///
    /// - Parameter event: The event to emit.
    public func emit(_ event: any Event) async {
        let eventHandlers = handlers.withLock { $0[event.name] ?? [] }
        for handler in eventHandlers {
            await handler(event)
        }
    }

    /// Registers a handler for an event.
    ///
    /// - Parameters:
    ///   - name: The event name to listen for.
    ///   - handler: The handler to call when the event is emitted.
    public func on(_ name: EventName, handler: @escaping Handler) {
        handlers.withLock { $0[name, default: []].append(handler) }
    }

    /// Removes all handlers for an event.
    ///
    /// - Parameter name: The event name.
    public func off(_ name: EventName) {
        handlers.withLock { _ = $0.removeValue(forKey: name) }
    }

    /// Removes all handlers for all events.
    public func removeAllHandlers() {
        handlers.withLock { $0.removeAll() }
    }
}

// MARK: - EmittingStep

/// A Step wrapper that emits events before and/or after execution.
public struct EmittingStep<Base: Step>: Step {
    public typealias Input = Base.Input
    public typealias Output = Base.Output

    private let base: Base
    private let stepName: String
    private let beforeEvents: [(EventName, ((any Sendable)?) -> (any Sendable)?)]
    private let afterEvents: [(EventName, (Output) -> (any Sendable)?)]

    init(
        base: Base,
        stepName: String? = nil,
        beforeEvents: [(EventName, ((any Sendable)?) -> (any Sendable)?)] = [],
        afterEvents: [(EventName, (Output) -> (any Sendable)?)] = []
    ) {
        self.base = base
        self.stepName = stepName ?? String(describing: type(of: base))
        self.beforeEvents = beforeEvents
        self.afterEvents = afterEvents
    }

    public func run(_ input: Input) async throws -> Output {
        // Get EventBus from context
        let eventBus = EventBusContext.current

        // Emit before events
        for (name, payloadBuilder) in beforeEvents {
            let event = StepEvent(
                name: name,
                stepName: stepName,
                value: payloadBuilder(nil)
            )
            await eventBus.emit(event)
        }

        // Run the base step
        let output = try await base.run(input)

        // Emit after events
        for (name, payloadBuilder) in afterEvents {
            let event = StepEvent(
                name: name,
                stepName: stepName,
                value: payloadBuilder(output)
            )
            await eventBus.emit(event)
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
                stepName: stepName,
                beforeEvents: beforeEvents + [(name, { _ in nil })],
                afterEvents: afterEvents
            )
        case .after:
            return EmittingStep(
                base: base,
                stepName: stepName,
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
                stepName: stepName,
                beforeEvents: beforeEvents + [(name, { _ in nil })],
                afterEvents: afterEvents
            )
        case .after:
            return EmittingStep(
                base: base,
                stepName: stepName,
                beforeEvents: beforeEvents,
                afterEvents: afterEvents + [(name, { payload($0) })]
            )
        }
    }
}
