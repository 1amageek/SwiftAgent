//
//  PermissionMode.swift
//  SwiftAgent
//
//  Created by SwiftAgent on 2025/01/23.
//

import Foundation

/// Permission modes that control the default behavior for tool authorization.
///
/// Permission modes provide a way to change the baseline permission behavior
/// for an entire session, making it easier to work in different contexts.
///
/// ## Modes
///
/// - `default`: Standard mode with normal permission checks
/// - `acceptEdits`: Auto-approve file modifications
/// - `plan`: Read-only mode for analysis without modifications
/// - `bypassPermissions`: Skip all permission checks (use with caution)
///
/// ## Usage
///
/// ```swift
/// let config = AgentConfiguration(
///     permissionMode: .acceptEdits  // Auto-approve file edits
/// )
/// ```
public enum PermissionMode: String, Codable, Sendable, CaseIterable {

    /// Standard mode with normal permission checks.
    ///
    /// All tools require appropriate permissions based on rules
    /// and delegate decisions.
    case `default`

    /// Auto-approve file edit operations.
    ///
    /// Tools that modify files (Edit, Write, MultiEdit) are
    /// automatically approved without prompting.
    case acceptEdits

    /// Plan mode for read-only analysis.
    ///
    /// Only read-only tools are allowed. Any tool that would
    /// modify files or execute commands is blocked.
    case plan

    /// Bypass all permission checks.
    ///
    /// All tools are automatically approved. Use this mode only
    /// in trusted, sandboxed environments.
    ///
    /// - Warning: This mode should only be used in controlled
    ///   environments where security is handled by other means.
    case bypassPermissions

    /// A description of this permission mode.
    public var description: String {
        switch self {
        case .default:
            return "Default - Standard permission checks"
        case .acceptEdits:
            return "Accept Edits - Auto-approve file modifications"
        case .plan:
            return "Plan - Read-only mode"
        case .bypassPermissions:
            return "Bypass - Skip all permission checks"
        }
    }

    /// Whether this mode allows write operations by default.
    public var allowsWritesByDefault: Bool {
        switch self {
        case .default:
            return false
        case .acceptEdits:
            return true
        case .plan:
            return false
        case .bypassPermissions:
            return true
        }
    }

    /// Whether this mode allows command execution by default.
    public var allowsExecutionByDefault: Bool {
        switch self {
        case .default:
            return false
        case .acceptEdits:
            return false
        case .plan:
            return false
        case .bypassPermissions:
            return true
        }
    }
}
