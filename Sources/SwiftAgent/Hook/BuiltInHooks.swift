//
//  BuiltInHooks.swift
//  SwiftAgent
//
//  Created by SwiftAgent on 2025/01/23.
//

import Foundation

// MARK: - Validation Hooks

/// A hook that validates file paths before file operations.
public struct PathValidationHookHandler: HookHandler {

    /// Allowed path prefixes.
    private let allowedPrefixes: [String]

    /// Denied path patterns.
    private let deniedPatterns: [String]

    public init(
        allowedPrefixes: [String] = [],
        deniedPatterns: [String] = [".env", "*.pem", "*.key", "*secret*", "*credential*"]
    ) {
        self.allowedPrefixes = allowedPrefixes
        self.deniedPatterns = deniedPatterns
    }

    public func execute(context: HookContext) async throws -> HookResult {
        guard let toolInput = context.toolInput,
              let toolName = context.toolName else {
            return .continue
        }

        // Only validate file-related tools
        let fileTools = ["Edit", "Write", "MultiEdit", "Read", "file_edit", "file_write", "file_read"]
        guard fileTools.contains(toolName) else {
            return .continue
        }

        // Extract path from JSON input
        guard let path = extractPath(from: toolInput) else {
            return .continue
        }

        // Check denied patterns
        for pattern in deniedPatterns {
            if matchesPattern(path, pattern: pattern) {
                return .block(reason: "Path '\(path)' matches denied pattern '\(pattern)'")
            }
        }

        // Check allowed prefixes if specified
        if !allowedPrefixes.isEmpty {
            let isAllowed = allowedPrefixes.contains { prefix in
                path.hasPrefix(prefix)
            }
            if !isAllowed {
                return .block(reason: "Path '\(path)' is outside allowed directories")
            }
        }

        return .continue
    }

    private func extractPath(from json: String) -> String? {
        // Simple extraction - look for "path" or "file_path" in JSON
        if let data = json.data(using: .utf8),
           let dict = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
            return dict["path"] as? String ?? dict["file_path"] as? String
        }
        return nil
    }

    private func matchesPattern(_ path: String, pattern: String) -> Bool {
        // Simple glob-style matching
        if pattern.hasPrefix("*") && pattern.hasSuffix("*") {
            let middle = String(pattern.dropFirst().dropLast())
            return path.contains(middle)
        } else if pattern.hasPrefix("*") {
            let suffix = String(pattern.dropFirst())
            return path.hasSuffix(suffix)
        } else if pattern.hasSuffix("*") {
            let prefix = String(pattern.dropLast())
            return path.hasPrefix(prefix)
        } else {
            return path == pattern || path.hasSuffix("/" + pattern)
        }
    }
}

/// A hook that validates command execution.
public struct CommandValidationHookHandler: HookHandler {

    /// Blocked command patterns.
    private let blockedPatterns: [String]

    /// Commands that require confirmation.
    private let confirmationPatterns: [String]

    public init(
        blockedPatterns: [String] = ["rm -rf /", "rm -rf /*", "sudo rm", "> /dev/sda"],
        confirmationPatterns: [String] = ["git push", "npm publish", "cargo publish"]
    ) {
        self.blockedPatterns = blockedPatterns
        self.confirmationPatterns = confirmationPatterns
    }

    public func execute(context: HookContext) async throws -> HookResult {
        guard let toolInput = context.toolInput,
              let toolName = context.toolName else {
            return .continue
        }

        // Only validate command tools
        let commandTools = ["Bash", "ExecuteCommand", "command_execute"]
        guard commandTools.contains(toolName) else {
            return .continue
        }

        // Extract command from JSON input
        guard let command = extractCommand(from: toolInput) else {
            return .continue
        }

        // Check blocked patterns
        for pattern in blockedPatterns {
            if command.contains(pattern) {
                return .block(reason: "Command contains blocked pattern: '\(pattern)'")
            }
        }

        // Check confirmation patterns
        for pattern in confirmationPatterns {
            if command.contains(pattern) {
                return .ask
            }
        }

        return .continue
    }

    private func extractCommand(from json: String) -> String? {
        if let data = json.data(using: .utf8),
           let dict = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
            return dict["command"] as? String
        }
        return nil
    }
}

// MARK: - Rate Limiting Hooks

/// A hook that implements rate limiting for tool calls.
public actor RateLimitingHookHandler: HookHandler {

    /// Maximum calls per window.
    private let maxCalls: Int

    /// Time window in seconds.
    private let windowSeconds: TimeInterval

    /// Call timestamps by tool name.
    private var callHistory: [String: [Date]] = [:]

    public init(maxCalls: Int = 100, windowSeconds: TimeInterval = 60) {
        self.maxCalls = maxCalls
        self.windowSeconds = windowSeconds
    }

    public func execute(context: HookContext) async throws -> HookResult {
        guard let toolName = context.toolName else {
            return .continue
        }

        let now = Date()
        let windowStart = now.addingTimeInterval(-windowSeconds)

        // Clean old entries
        callHistory[toolName] = callHistory[toolName]?.filter { $0 > windowStart } ?? []

        // Check rate limit
        let callCount = callHistory[toolName]?.count ?? 0
        if callCount >= maxCalls {
            return .block(reason: "Rate limit exceeded for \(toolName): \(callCount)/\(maxCalls) calls in \(Int(windowSeconds))s")
        }

        // Record this call
        if callHistory[toolName] == nil {
            callHistory[toolName] = []
        }
        callHistory[toolName]?.append(now)

        return .continue
    }
}

// MARK: - Telemetry Hooks

/// A hook that collects telemetry about tool usage.
public actor TelemetryHookHandler: HookHandler {

    /// Collected metrics.
    public struct Metrics: Sendable {
        public let totalCalls: Int
        public let callsByTool: [String: Int]
        public let averageDuration: [String: Duration]
        public let errors: Int
    }

    private var totalCalls: Int = 0
    private var callsByTool: [String: Int] = [:]
    private var durations: [String: [Duration]] = [:]
    private var errors: Int = 0

    public init() {}

    public func execute(context: HookContext) async throws -> HookResult {
        guard let toolName = context.toolName else {
            return .continue
        }

        switch context.event {
        case .preToolUse:
            totalCalls += 1
            callsByTool[toolName, default: 0] += 1

        case .postToolUse:
            if let duration = context.executionDuration {
                if durations[toolName] == nil {
                    durations[toolName] = []
                }
                durations[toolName]?.append(duration)
            }

        default:
            break
        }

        if context.error != nil {
            errors += 1
        }

        return .continue
    }

    /// Gets the current metrics.
    public func getMetrics() -> Metrics {
        let averages = durations.mapValues { durationList -> Duration in
            guard !durationList.isEmpty else { return .zero }
            let totalNanos = durationList.reduce(0) { $0 + Int64($1.components.attoseconds / 1_000_000_000) }
            return .nanoseconds(totalNanos / Int64(durationList.count))
        }

        return Metrics(
            totalCalls: totalCalls,
            callsByTool: callsByTool,
            averageDuration: averages,
            errors: errors
        )
    }

    /// Resets the collected metrics.
    public func reset() {
        totalCalls = 0
        callsByTool.removeAll()
        durations.removeAll()
        errors = 0
    }
}

// MARK: - Context Injection Hooks

/// A hook that injects context into conversations.
public struct ContextInjectionHookHandler: HookHandler {

    /// The context to inject.
    private let contextProvider: @Sendable () async -> String?

    public init(contextProvider: @escaping @Sendable () async -> String?) {
        self.contextProvider = contextProvider
    }

    public func execute(context: HookContext) async throws -> HookResult {
        if let contextMessage = await contextProvider() {
            return .addContext(contextMessage)
        }
        return .continue
    }
}

// MARK: - Session Lifecycle Hooks

/// A hook that runs setup tasks at session start.
public struct SessionSetupHookHandler: HookHandler {

    private let setup: @Sendable () async throws -> Void

    public init(setup: @escaping @Sendable () async throws -> Void) {
        self.setup = setup
    }

    public func execute(context: HookContext) async throws -> HookResult {
        if context.event == .sessionStart {
            try await setup()
        }
        return .continue
    }
}

/// A hook that runs cleanup tasks at session end.
public struct SessionCleanupHookHandler: HookHandler {

    private let cleanup: @Sendable () async throws -> Void

    public init(cleanup: @escaping @Sendable () async throws -> Void) {
        self.cleanup = cleanup
    }

    public func execute(context: HookContext) async throws -> HookResult {
        if context.event == .sessionEnd {
            try await cleanup()
        }
        return .continue
    }
}

// MARK: - Notification Hooks

/// A hook that sends notifications for important events.
public struct NotificationHookHandler: HookHandler {

    /// The notification handler.
    private let handler: @Sendable (String, HookContext) async -> Void

    /// Events that trigger notifications.
    private let notifyOn: Set<HookEvent>

    /// Tool names that trigger notifications (empty means all).
    private let toolFilter: Set<String>

    public init(
        notifyOn: Set<HookEvent> = [.postToolUse],
        toolFilter: Set<String> = [],
        handler: @escaping @Sendable (String, HookContext) async -> Void
    ) {
        self.notifyOn = notifyOn
        self.toolFilter = toolFilter
        self.handler = handler
    }

    public func execute(context: HookContext) async throws -> HookResult {
        guard notifyOn.contains(context.event) else {
            return .continue
        }

        // Check tool filter
        if !toolFilter.isEmpty {
            guard let toolName = context.toolName,
                  toolFilter.contains(toolName) else {
                return .continue
            }
        }

        // Build notification message
        let message = buildMessage(for: context)
        await handler(message, context)

        return .continue
    }

    private func buildMessage(for context: HookContext) -> String {
        switch context.event {
        case .preToolUse:
            return "Starting: \(context.toolName ?? "unknown")"
        case .postToolUse:
            let duration = context.executionDuration.map { String(describing: $0) } ?? "unknown"
            return "Completed: \(context.toolName ?? "unknown") in \(duration)"
        case .sessionStart:
            return "Session started"
        case .sessionEnd:
            return "Session ended"
        default:
            return "Event: \(context.event.rawValue)"
        }
    }
}
