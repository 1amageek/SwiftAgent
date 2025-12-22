//
//  HookManager.swift
//  SwiftAgent
//
//  Created by SwiftAgent on 2025/01/23.
//

import Foundation

/// A registered hook with its matcher and handler.
public struct RegisteredHook: Sendable {

    /// Unique identifier for this registration.
    public let id: String

    /// The event this hook responds to.
    public let event: HookEvent

    /// Optional matcher to filter which tools trigger this hook.
    public let matcher: ToolMatcher?

    /// The hook handler.
    public let handler: any HookHandler

    /// Priority for ordering (higher runs first).
    public let priority: Int

    /// Creates a registered hook.
    public init(
        id: String = UUID().uuidString,
        event: HookEvent,
        matcher: ToolMatcher? = nil,
        handler: any HookHandler,
        priority: Int = 0
    ) {
        self.id = id
        self.event = event
        self.matcher = matcher
        self.handler = handler
        self.priority = priority
    }
}

/// Protocol for hook handlers.
public protocol HookHandler: Sendable {

    /// Executes the hook.
    ///
    /// - Parameter context: The hook context.
    /// - Returns: The hook result.
    func execute(context: HookContext) async throws -> HookResult
}

/// Manages hook registration and execution.
///
/// `HookManager` is an actor that handles all hook-related operations,
/// including registration, matching, and parallel execution.
///
/// ## Usage
///
/// ```swift
/// let manager = HookManager()
///
/// // Register a logging hook for all tools
/// await manager.register(
///     LoggingHookHandler(),
///     for: .preToolUse
/// )
///
/// // Register a validation hook for specific tools
/// await manager.register(
///     ValidatePathHookHandler(),
///     for: .preToolUse,
///     matcher: ToolMatcher(pattern: "Edit|Write")
/// )
///
/// // Execute hooks
/// let result = try await manager.execute(
///     event: .preToolUse,
///     context: context
/// )
/// ```
public actor HookManager {

    // MARK: - Properties

    /// Registered hooks by event type.
    private var hooks: [HookEvent: [RegisteredHook]] = [:]

    /// Session-started flag for sessionStart deduplication.
    private var sessionStarted: Bool = false

    // MARK: - Initialization

    /// Creates a new hook manager.
    public init() {}

    // MARK: - Registration

    /// Registers a hook handler for an event.
    ///
    /// - Parameters:
    ///   - handler: The hook handler.
    ///   - event: The event to listen for.
    ///   - matcher: Optional matcher to filter triggers.
    ///   - priority: Priority for ordering (higher runs first).
    /// - Returns: The registration ID.
    @discardableResult
    public func register(
        _ handler: any HookHandler,
        for event: HookEvent,
        matcher: ToolMatcher? = nil,
        priority: Int = 0
    ) -> String {
        let registration = RegisteredHook(
            event: event,
            matcher: matcher,
            handler: handler,
            priority: priority
        )

        if hooks[event] == nil {
            hooks[event] = []
        }
        hooks[event]?.append(registration)

        // Sort by priority (descending)
        hooks[event]?.sort { $0.priority > $1.priority }

        return registration.id
    }

    /// Registers a hook using the legacy ToolExecutionHook protocol.
    ///
    /// - Parameters:
    ///   - hook: The legacy hook.
    ///   - matcher: Optional matcher.
    ///   - priority: Priority for ordering.
    @discardableResult
    public func register(
        legacyHook hook: any ToolExecutionHook,
        matcher: ToolMatcher? = nil,
        priority: Int = 0
    ) -> [String] {
        let adapter = LegacyHookAdapter(hook: hook)

        let preID = register(adapter, for: .preToolUse, matcher: matcher, priority: priority)
        let postID = register(adapter, for: .postToolUse, matcher: matcher, priority: priority)

        return [preID, postID]
    }

    /// Unregisters a hook by ID.
    ///
    /// - Parameter id: The registration ID.
    public func unregister(id: String) {
        for event in HookEvent.allCases {
            hooks[event]?.removeAll { $0.id == id }
        }
    }

    /// Removes all hooks for an event.
    public func clearHooks(for event: HookEvent) {
        hooks[event]?.removeAll()
    }

    /// Removes all hooks.
    public func clearAllHooks() {
        hooks.removeAll()
    }

    /// Gets count of registered hooks for an event.
    public func hookCount(for event: HookEvent) -> Int {
        hooks[event]?.count ?? 0
    }

    // MARK: - Execution

    /// Executes all matching hooks for an event.
    ///
    /// Hooks are executed in parallel (grouped by priority level),
    /// and results are aggregated.
    ///
    /// - Parameters:
    ///   - event: The event type.
    ///   - context: The hook context.
    /// - Returns: The aggregated result.
    public func execute(
        event: HookEvent,
        context: HookContext
    ) async throws -> AggregatedHookResult {

        // Handle sessionStart deduplication
        if event == .sessionStart {
            if sessionStarted {
                return AggregatedHookResult(decision: .continue)
            }
            sessionStarted = true
        }

        // Get matching hooks
        let matchingHooks = getMatchingHooks(event: event, context: context)

        if matchingHooks.isEmpty {
            return AggregatedHookResult(decision: .continue)
        }

        // Execute hooks in parallel
        var results: [HookResult] = []

        // Group by priority for ordered execution
        let priorityGroups = Dictionary(grouping: matchingHooks) { $0.priority }
        let sortedPriorities = priorityGroups.keys.sorted(by: >)

        for priority in sortedPriorities {
            guard let hooksAtPriority = priorityGroups[priority] else { continue }

            // Execute same-priority hooks in parallel
            let groupResults = try await withThrowingTaskGroup(of: HookResult.self) { group in
                for hook in hooksAtPriority {
                    group.addTask {
                        try await hook.handler.execute(context: context)
                    }
                }

                var collected: [HookResult] = []
                for try await result in group {
                    collected.append(result)
                }
                return collected
            }

            results.append(contentsOf: groupResults)

            // Check for blocking results before continuing to lower priorities
            let aggregated = AggregatedHookResult.aggregate(results)
            if !aggregated.decision.allowsExecution {
                return aggregated
            }
        }

        return AggregatedHookResult.aggregate(results)
    }

    /// Resets session state (for testing or new sessions).
    public func resetSession() {
        sessionStarted = false
    }

    // MARK: - Private Methods

    private func getMatchingHooks(event: HookEvent, context: HookContext) -> [RegisteredHook] {
        guard let eventHooks = hooks[event] else {
            return []
        }

        return eventHooks.filter { hook in
            // If no matcher, hook matches all
            guard let matcher = hook.matcher else {
                return true
            }

            // For tool events, match against tool name and input
            if event.isToolEvent {
                guard let toolName = context.toolName else {
                    return false
                }
                return matcher.matches(toolName: toolName, arguments: context.toolInput)
            }

            // For other events, match against tool name if present
            if let toolName = context.toolName {
                return matcher.matches(toolName: toolName, arguments: context.toolInput)
            }

            return true
        }
    }
}

// MARK: - Legacy Hook Adapter

/// Adapts the legacy ToolExecutionHook to the new HookHandler protocol.
private struct LegacyHookAdapter: HookHandler {

    let hook: any ToolExecutionHook

    func execute(context: HookContext) async throws -> HookResult {
        guard let toolName = context.toolName,
              let toolInput = context.toolInput else {
            return .continue
        }

        switch context.event {
        case .preToolUse:
            // Convert ToolExecutionContext
            let execContext = ToolExecutionContext(
                sessionID: context.sessionID,
                traceID: context.traceID
            )

            let decision = try await hook.beforeExecution(
                toolName: toolName,
                arguments: toolInput,
                context: execContext
            )

            switch decision {
            case .proceed:
                return .continue
            case .proceedWithModifiedArgs(let modified):
                return .allowWithModifiedInput(modified)
            case .block(let reason):
                return .block(reason: reason)
            case .requireApproval:
                return .ask
            }

        case .postToolUse:
            guard let output = context.toolOutput,
                  let duration = context.executionDuration else {
                return .continue
            }

            let execContext = ToolExecutionContext(
                sessionID: context.sessionID,
                traceID: context.traceID
            )

            try await hook.afterExecution(
                toolName: toolName,
                arguments: toolInput,
                output: output,
                duration: duration,
                context: execContext
            )
            return .continue

        default:
            return .continue
        }
    }
}

// MARK: - Convenience Hook Handlers

/// A simple closure-based hook handler.
public struct ClosureHookHandler: HookHandler {

    private let closure: @Sendable (HookContext) async throws -> HookResult

    public init(_ closure: @escaping @Sendable (HookContext) async throws -> HookResult) {
        self.closure = closure
    }

    public func execute(context: HookContext) async throws -> HookResult {
        try await closure(context)
    }
}

/// A logging hook handler.
public struct LoggingHookHandler: HookHandler {

    private let logger: @Sendable (String) -> Void

    public init(logger: @escaping @Sendable (String) -> Void = { print($0) }) {
        self.logger = logger
    }

    public func execute(context: HookContext) async throws -> HookResult {
        switch context.event {
        case .preToolUse:
            if let toolName = context.toolName {
                logger("[\(context.event.rawValue)] Executing \(toolName)")
            }
        case .postToolUse:
            if let toolName = context.toolName, let duration = context.executionDuration {
                logger("[\(context.event.rawValue)] Completed \(toolName) in \(duration)")
            }
        case .sessionStart:
            logger("[\(context.event.rawValue)] Session started")
        case .sessionEnd:
            logger("[\(context.event.rawValue)] Session ended")
        default:
            logger("[\(context.event.rawValue)] Event fired")
        }
        return .continue
    }
}
