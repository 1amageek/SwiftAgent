//
//  PermissionMiddleware.swift
//  SwiftAgent
//
//  Created by SwiftAgent on 2025/01/04.
//

import Foundation
import Synchronization

/// Error thrown when permission is denied.
public struct PermissionDenied: Error, LocalizedError, Sendable {
    /// The tool that was denied.
    public let toolName: String

    /// The reason for denial.
    public let reason: String?

    /// The matched rule (if any).
    public let matchedRule: PermissionRule?

    public init(
        toolName: String,
        reason: String? = nil,
        matchedRule: PermissionRule? = nil
    ) {
        self.toolName = toolName
        self.reason = reason
        self.matchedRule = matchedRule
    }

    public var errorDescription: String? {
        var message = "Permission denied for '\(toolName)'"
        if let reason = reason {
            message += ": \(reason)"
        }
        if let rule = matchedRule {
            message += " (matched rule: \(rule.pattern))"
        }
        return message
    }
}

/// Middleware that enforces permission rules for tool execution.
///
/// This middleware evaluates the permission configuration, handles
/// interactive confirmation via the permission handler, and maintains
/// session memory for "Always Allow" and "Block" decisions.
///
/// ## Example
///
/// ```swift
/// let config = PermissionConfiguration.standard
///     .withHandler(CLIPermissionHandler())
///
/// let middleware = PermissionMiddleware(configuration: config)
///
/// let pipeline = ToolPipeline()
///     .use(middleware)
/// ```
///
/// ## Rule Evaluation Order
///
/// 1. Session memory (alwaysAllow / blocked)
/// 2. Allow rules (first match wins)
/// 3. Deny rules (first match wins)
/// 4. Default action (allow / deny / ask)
public struct PermissionMiddleware: ToolMiddleware, Sendable {

    private let configuration: PermissionConfiguration

    /// Session memory state container (reference type to hold Mutex).
    private final class StateContainer: @unchecked Sendable {
        struct SessionState {
            var allowed: Set<String> = []
            var blocked: Set<String> = []
        }

        let mutex: Mutex<SessionState>

        init() {
            self.mutex = Mutex(SessionState())
        }

        func withLock<T: Sendable>(_ body: (inout SessionState) -> sending T) -> T {
            mutex.withLock(body)
        }
    }

    /// Thread-safe session memory.
    private let state: StateContainer

    /// Creates a permission middleware.
    ///
    /// - Parameter configuration: The permission configuration.
    public init(configuration: PermissionConfiguration) {
        self.configuration = configuration
        self.state = StateContainer()
    }

    // MARK: - ToolMiddleware

    public func handle(
        _ context: ToolContext,
        next: @escaping Next
    ) async throws -> ToolResult {
        // Generate a key for session memory
        let memoryKey = generateMemoryKey(for: context)

        // 1. Check session memory
        if configuration.enableSessionMemory {
            let (isAllowed, isBlocked) = state.withLock { state in
                (state.allowed.contains(memoryKey), state.blocked.contains(memoryKey))
            }

            if isAllowed {
                return try await next(context)
            }

            if isBlocked {
                throw PermissionDenied(
                    toolName: context.toolName,
                    reason: "Pattern blocked earlier in session"
                )
            }
        }

        // 2. Check allow rules (first match wins)
        for rule in configuration.allow {
            if rule.matches(context) {
                return try await next(context)
            }
        }

        // 3. Check deny rules
        for rule in configuration.deny {
            if rule.matches(context) {
                throw PermissionDenied(
                    toolName: context.toolName,
                    reason: "Matched deny rule",
                    matchedRule: rule
                )
            }
        }

        // 4. Apply default action
        switch configuration.defaultAction {
        case .allow:
            return try await next(context)

        case .deny:
            throw PermissionDenied(
                toolName: context.toolName,
                reason: "No matching rule and default is deny"
            )

        case .ask:
            return try await promptUser(context: context, memoryKey: memoryKey, next: next)
        }
    }

    // MARK: - Private Methods

    /// Generates a key for session memory based on the tool context.
    ///
    /// For Bash commands, uses the first word of the command.
    /// For file operations, uses the file path.
    /// For other tools, uses just the tool name.
    private func generateMemoryKey(for context: ToolContext) -> String {
        // Parse arguments to get more specific key
        if let data = context.arguments.data(using: .utf8),
           let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {

            // For Bash, use first word of command
            if context.toolName == "Bash" || context.toolName == "ExecuteCommand" {
                if let command = json["command"] as? String {
                    let firstWord = command.split(separator: " ").first.map(String.init) ?? command
                    return "\(context.toolName):\(firstWord)"
                }
            }

            // For file tools, use the path
            if let filePath = json["file_path"] as? String ?? json["path"] as? String {
                // Use directory for grouping
                let directory = (filePath as NSString).deletingLastPathComponent
                return "\(context.toolName):\(directory)"
            }
        }

        return context.toolName
    }

    /// Prompts the user for permission.
    private func promptUser(
        context: ToolContext,
        memoryKey: String,
        next: @escaping Next
    ) async throws -> ToolResult {
        guard let handler = configuration.handler else {
            throw PermissionDenied(
                toolName: context.toolName,
                reason: "No permission handler configured and default is 'ask'"
            )
        }

        let request = PermissionRequest(from: context)
        let response = try await handler.requestPermission(request)

        // Update session memory
        if configuration.enableSessionMemory {
            state.withLock { state in
                switch response {
                case .alwaysAllow:
                    state.allowed.insert(memoryKey)
                case .denyAndBlock:
                    state.blocked.insert(memoryKey)
                default:
                    break
                }
            }
        }

        // Process response
        switch response {
        case .allowOnce, .alwaysAllow:
            return try await next(context)

        case .deny, .denyAndBlock:
            throw PermissionDenied(
                toolName: context.toolName,
                reason: "User denied permission"
            )
        }
    }

    // MARK: - Session Management

    /// Resets the session memory.
    ///
    /// Clears all "always allow" and "block" decisions.
    public func resetSessionMemory() {
        state.withLock { state in
            state.allowed.removeAll()
            state.blocked.removeAll()
        }
    }

    /// Returns the current "always allowed" patterns.
    public var alwaysAllowedPatterns: Set<String> {
        state.withLock { $0.allowed }
    }

    /// Returns the current "blocked" patterns.
    public var blockedPatterns: Set<String> {
        state.withLock { $0.blocked }
    }
}
