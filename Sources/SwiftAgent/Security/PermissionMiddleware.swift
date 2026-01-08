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

/// A provider of dynamic permission rules.
///
/// This type alias allows external modules (like SwiftAgentSkills) to
/// inject permission rules that are evaluated at runtime.
public typealias DynamicPermissionRulesProvider = @Sendable () -> [PermissionRule]

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
/// ## Dynamic Permission Rules
///
/// External modules can inject dynamic rules via the `dynamicRulesProvider`:
///
/// ```swift
/// let skillPermissions = SkillPermissions()
/// let middleware = PermissionMiddleware(
///     configuration: config,
///     dynamicRulesProvider: { skillPermissions.rules }
/// )
/// ```
///
/// ## Rule Evaluation Order
///
/// 1. Final deny rules (ALWAYS checked first, cannot be bypassed)
/// 2. Session memory (alwaysAllow / blocked)
/// 3. Override rules (skip regular deny if matched)
/// 4. Deny rules (first match wins) - can be overridden
/// 5. Allow rules (first match wins) - includes dynamic rules from skills
/// 6. Default action (allow / deny / ask)
///
/// **Security Note**: Dynamic rules (from skills) are added to the allow list,
/// which is evaluated AFTER deny rules. This means skills cannot bypass
/// deny or finalDeny rules - they can only pre-approve tools that would
/// otherwise require user confirmation (default action = ask).
public struct PermissionMiddleware: ToolMiddleware, Sendable {

    /// The base permission configuration.
    public let configuration: PermissionConfiguration

    /// Provider for dynamic permission rules (e.g., from activated skills).
    private let dynamicRulesProvider: DynamicPermissionRulesProvider?

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
        self.dynamicRulesProvider = nil
        self.state = StateContainer()
    }

    /// Creates a permission middleware with dynamic rules support.
    ///
    /// Dynamic rules are added to the allow list and evaluated after deny rules
    /// but before static allow rules. This is used for skill-granted permissions.
    ///
    /// - Parameters:
    ///   - configuration: The permission configuration.
    ///   - dynamicRulesProvider: A closure that returns dynamic permission rules.
    public init(
        configuration: PermissionConfiguration,
        dynamicRulesProvider: DynamicPermissionRulesProvider?
    ) {
        self.configuration = configuration
        self.dynamicRulesProvider = dynamicRulesProvider
        self.state = StateContainer()
    }

    // MARK: - ToolMiddleware

    public func handle(
        _ context: ToolContext,
        next: @escaping Next
    ) async throws -> ToolResult {
        // Get effective configuration (merged with guardrail if present)
        let effectiveConfig = effectiveConfiguration()

        // Generate a key for session memory
        let memoryKey = generateMemoryKey(for: context)

        // 1. ALWAYS check final deny rules first (cannot be bypassed by session memory)
        //    This ensures security-critical restrictions are never circumvented.
        for rule in effectiveConfig.finalDeny {
            if rule.matches(context) {
                throw PermissionDenied(
                    toolName: context.toolName,
                    reason: "Matched final deny rule (cannot be overridden)",
                    matchedRule: rule
                )
            }
        }

        // 2. Check session memory (for non-finalDeny cases)
        if effectiveConfig.enableSessionMemory {
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

        // 3. Check override rules (skip regular deny if matched)
        let isOverridden = effectiveConfig.overrides.contains { $0.matches(context) }

        // 4. Check regular deny rules (if not overridden)
        if !isOverridden {
            for rule in effectiveConfig.deny {
                if rule.matches(context) {
                    throw PermissionDenied(
                        toolName: context.toolName,
                        reason: "Matched deny rule",
                        matchedRule: rule
                    )
                }
            }
        }

        // 5. Check allow rules
        for rule in effectiveConfig.allow {
            if rule.matches(context) {
                return try await next(context)
            }
        }

        // 6. Apply default action
        switch effectiveConfig.defaultAction {
        case .allow:
            return try await next(context)

        case .deny:
            throw PermissionDenied(
                toolName: context.toolName,
                reason: "No matching rule and default is deny"
            )

        case .ask:
            return try await promptUser(
                context: context,
                memoryKey: memoryKey,
                effectiveConfig: effectiveConfig,
                next: next
            )
        }
    }

    // MARK: - Guardrail Integration

    /// Gets the effective permission configuration, merging with guardrail context
    /// and dynamic rules if present.
    ///
    /// Evaluation order:
    /// 1. Guardrail rules (step-level) take precedence
    /// 2. Dynamic rules (e.g., from skills) are added to allow list
    /// 3. Base configuration rules
    private func effectiveConfiguration() -> PermissionConfiguration {
        var config = configuration

        // Merge guardrail context if present
        let guardrailConfig = GuardrailContext.current
        if guardrailConfig.hasPermissionRules {
            config = guardrailConfig.mergedPermissions(with: config)
        }

        // Add dynamic rules to allow list (e.g., from activated skills)
        if let provider = dynamicRulesProvider {
            let dynamicRules = provider()
            if !dynamicRules.isEmpty {
                // Dynamic rules are prepended to allow list for priority
                var updatedConfig = config
                updatedConfig.allow = dynamicRules + config.allow
                config = updatedConfig
            }
        }

        return config
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
        effectiveConfig: PermissionConfiguration,
        next: @escaping Next
    ) async throws -> ToolResult {
        guard let handler = effectiveConfig.handler else {
            throw PermissionDenied(
                toolName: context.toolName,
                reason: "No permission handler configured and default is 'ask'"
            )
        }

        let request = PermissionRequest(from: context)
        let response = try await handler.requestPermission(request)

        // Update session memory
        if effectiveConfig.enableSessionMemory {
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
