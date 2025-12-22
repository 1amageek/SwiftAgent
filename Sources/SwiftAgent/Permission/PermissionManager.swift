//
//  PermissionManager.swift
//  SwiftAgent
//
//  Created by SwiftAgent on 2025/01/23.
//

import Foundation

/// The result of a permission check.
public enum PermissionCheckResult: Sendable, Equatable {
    /// The operation is allowed.
    case allowed

    /// The operation is allowed with modified input.
    case allowedWithModifiedInput(String)

    /// The operation is denied.
    case denied(reason: String?)

    /// User approval is required.
    case askRequired

    /// Whether the operation can proceed.
    public var canProceed: Bool {
        switch self {
        case .allowed, .allowedWithModifiedInput:
            return true
        case .denied, .askRequired:
            return false
        }
    }
}

/// Manages permission rules and checks for tool usage.
///
/// `PermissionManager` is an actor that centralizes all permission-related logic,
/// including rule evaluation, mode checking, and delegate callbacks.
///
/// ## Rule Precedence
///
/// Rules are evaluated in the following order:
/// 1. Deny rules (highest priority)
/// 2. Ask rules
/// 3. Allow rules
/// 4. Permission mode defaults
/// 5. Delegate callback (lowest priority)
///
/// ## Usage
///
/// ```swift
/// let manager = PermissionManager()
///
/// // Add rules
/// await manager.addRule(.deny("Bash(rm -rf:*)"))
/// await manager.addRule(.allow("Read"))
/// await manager.addRule(.ask("Edit"))
///
/// // Check permission
/// let result = try await manager.checkPermission(
///     toolName: "Edit",
///     arguments: "{\"path\": \"/src/main.swift\"}",
///     context: context
/// )
/// ```
public actor PermissionManager {

    // MARK: - Properties

    /// Current permission mode.
    private var mode: PermissionMode = .default

    /// Deny rules (checked first).
    private var denyRules: [PermissionRule] = []

    /// Ask rules (checked second).
    private var askRules: [PermissionRule] = []

    /// Allow rules (checked third).
    private var allowRules: [PermissionRule] = []

    /// Permission delegate for custom logic.
    private var delegate: (any ToolPermissionDelegate)?

    /// Tool-level permission mappings.
    private var toolLevels: [String: ToolPermissionLevel] = [:]

    /// Maximum allowed permission level.
    private var maxLevel: ToolPermissionLevel = .dangerous

    // MARK: - Initialization

    /// Creates a new permission manager.
    ///
    /// - Parameters:
    ///   - mode: Initial permission mode.
    ///   - rules: Initial rules to add.
    ///   - delegate: Optional permission delegate.
    public init(
        mode: PermissionMode = .default,
        rules: [PermissionRule] = [],
        delegate: (any ToolPermissionDelegate)? = nil
    ) {
        self.mode = mode
        self.delegate = delegate

        // Add rules synchronously during init (actor is uninitialized)
        for rule in rules {
            switch rule.type {
            case .deny:
                if !denyRules.contains(rule) {
                    denyRules.append(rule)
                }
            case .ask:
                if !askRules.contains(rule) {
                    askRules.append(rule)
                }
            case .allow:
                if !allowRules.contains(rule) {
                    allowRules.append(rule)
                }
            }
        }
    }

    // MARK: - Configuration

    /// Sets the permission mode.
    public func setMode(_ mode: PermissionMode) {
        self.mode = mode
    }

    /// Gets the current permission mode.
    public func getMode() -> PermissionMode {
        mode
    }

    /// Sets the permission delegate.
    public func setDelegate(_ delegate: (any ToolPermissionDelegate)?) {
        self.delegate = delegate
    }

    /// Adds a permission rule.
    public func addRule(_ rule: PermissionRule) {
        addRuleInternal(rule)
    }

    /// Adds multiple permission rules.
    public func addRules(_ rules: [PermissionRule]) {
        for rule in rules {
            addRuleInternal(rule)
        }
    }

    /// Removes all rules.
    public func clearRules() {
        denyRules.removeAll()
        askRules.removeAll()
        allowRules.removeAll()
    }

    /// Sets tool permission levels.
    public func setToolLevels(_ levels: [String: ToolPermissionLevel]) {
        self.toolLevels = levels
    }

    /// Sets maximum allowed permission level.
    public func setMaxLevel(_ level: ToolPermissionLevel) {
        self.maxLevel = level
    }

    // MARK: - Permission Checking

    /// Checks if a tool can be used.
    ///
    /// - Parameters:
    ///   - toolName: The name of the tool.
    ///   - arguments: The JSON-encoded arguments.
    ///   - context: The permission context.
    /// - Returns: The permission check result.
    public func checkPermission(
        toolName: String,
        arguments: String,
        context: ToolPermissionContext
    ) async throws -> PermissionCheckResult {

        // 1. Check deny rules first (highest priority)
        for rule in denyRules {
            let matcher = ToolMatcher(pattern: rule.pattern)
            if matcher.matches(toolName: toolName, arguments: arguments) {
                return .denied(reason: "Denied by rule: \(rule.pattern)")
            }
        }

        // 2. Check tool permission level
        let toolLevel = toolLevels[toolName] ?? .standard
        if toolLevel > maxLevel {
            return .denied(reason: "Tool '\(toolName)' requires \(toolLevel.description) permission, but max is \(maxLevel.description)")
        }

        // 3. Check ask rules
        for rule in askRules {
            let matcher = ToolMatcher(pattern: rule.pattern)
            if matcher.matches(toolName: toolName, arguments: arguments) {
                // Ask rule matched - need confirmation unless bypassed
                if mode == .bypassPermissions {
                    return .allowed
                }
                return .askRequired
            }
        }

        // 4. Check allow rules
        for rule in allowRules {
            let matcher = ToolMatcher(pattern: rule.pattern)
            if matcher.matches(toolName: toolName, arguments: arguments) {
                return .allowed
            }
        }

        // 5. Apply permission mode defaults
        switch mode {
        case .bypassPermissions:
            return .allowed

        case .plan:
            // In plan mode, only allow read-only tools
            if isReadOnlyTool(toolName) {
                return .allowed
            }
            return .denied(reason: "Plan mode: only read-only operations allowed")

        case .acceptEdits:
            // Auto-approve file modifications
            if isWriteTool(toolName) {
                return .allowed
            }
            // Fall through to delegate check

        case .default:
            break // Fall through to delegate check
        }

        // 6. Check with delegate (if any)
        if let delegate = delegate {
            let result = try await delegate.canUseTool(
                named: toolName,
                arguments: arguments,
                context: context
            )

            switch result {
            case .allow:
                return .allowed
            case .allowWithModifiedInput(let modified):
                return .allowedWithModifiedInput(modified)
            case .deny(let reason):
                return .denied(reason: reason)
            case .denyAndInterrupt(let reason):
                throw PermissionError.deniedByDelegate(toolName: toolName, reason: reason)
            }
        }

        // 7. Default behavior based on mode
        switch mode {
        case .default:
            return .askRequired
        case .acceptEdits, .bypassPermissions:
            return .allowed
        case .plan:
            return .denied(reason: "Plan mode: operation not allowed")
        }
    }

    /// Quick check if a tool is likely allowed (without full evaluation).
    public func quickCheck(toolName: String) -> Bool {
        // Check deny rules
        for rule in denyRules {
            let matcher = ToolMatcher(pattern: rule.pattern)
            if matcher.matches(toolName: toolName) {
                return false
            }
        }

        // Check allow rules
        for rule in allowRules {
            let matcher = ToolMatcher(pattern: rule.pattern)
            if matcher.matches(toolName: toolName) {
                return true
            }
        }

        // Check mode
        return mode == .bypassPermissions
    }

    // MARK: - Private Methods

    private func addRuleInternal(_ rule: PermissionRule) {
        switch rule.type {
        case .deny:
            if !denyRules.contains(rule) {
                denyRules.append(rule)
            }
        case .ask:
            if !askRules.contains(rule) {
                askRules.append(rule)
            }
        case .allow:
            if !allowRules.contains(rule) {
                allowRules.append(rule)
            }
        }
    }

    private func isReadOnlyTool(_ name: String) -> Bool {
        let readOnlyTools: Set<String> = [
            "Read", "file_read",
            "Glob", "file_pattern",
            "Grep", "text_search",
            "WebFetch", "web_fetch",
            "WebSearch", "web_search"
        ]
        return readOnlyTools.contains(name)
    }

    private func isWriteTool(_ name: String) -> Bool {
        let writeTools: Set<String> = [
            "Write", "file_write",
            "Edit", "file_edit",
            "MultiEdit", "file_multi_edit"
        ]
        return writeTools.contains(name)
    }
}

// MARK: - Default Tool Levels

extension PermissionManager {

    /// Default tool permission levels.
    public static let defaultToolLevels: [String: ToolPermissionLevel] = [
        // Read-only
        "Read": .readOnly,
        "file_read": .readOnly,
        "Glob": .readOnly,
        "file_pattern": .readOnly,
        "Grep": .readOnly,
        "text_search": .readOnly,

        // Standard
        "WebFetch": .standard,
        "web_fetch": .standard,
        "WebSearch": .standard,
        "web_search": .standard,

        // Elevated (file modifications)
        "Write": .elevated,
        "file_write": .elevated,
        "Edit": .elevated,
        "file_edit": .elevated,
        "MultiEdit": .elevated,
        "file_multi_edit": .elevated,

        // Dangerous (command execution)
        "Bash": .dangerous,
        "ExecuteCommand": .dangerous,
        "command_execute": .dangerous,
        "Git": .dangerous,
        "git_command": .dangerous
    ]
}
