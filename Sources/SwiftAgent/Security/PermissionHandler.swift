//
//  PermissionHandler.swift
//  SwiftAgent
//
//  Created by SwiftAgent on 2025/01/04.
//

import Foundation

/// User's response to a permission prompt.
public enum PermissionResponse: Sendable {
    /// Allow this specific invocation only.
    case allowOnce

    /// Always allow this tool/command pattern for the session.
    case alwaysAllow

    /// Deny this invocation.
    case deny

    /// Deny and block this pattern for the session.
    case denyAndBlock
}

/// A request for permission to execute a tool.
///
/// Contains all information about the tool invocation for the handler
/// to make a decision.
public struct PermissionRequest: Sendable {

    /// The session ID (if available).
    public let sessionID: String?

    /// The tool being invoked.
    public let toolName: String

    /// The tool arguments as a dictionary.
    public let toolInput: [String: String]

    /// The tool use ID (if available).
    public let toolUseID: String?

    /// Creates a permission request.
    public init(
        sessionID: String? = nil,
        toolName: String,
        toolInput: [String: String],
        toolUseID: String? = nil
    ) {
        self.sessionID = sessionID
        self.toolName = toolName
        self.toolInput = toolInput
        self.toolUseID = toolUseID
    }

    /// Creates a permission request from a tool context.
    public init(from context: ToolContext) {
        self.sessionID = context.sessionID
        self.toolName = context.toolName
        self.toolUseID = context.toolUseID

        // Parse arguments JSON
        if let data = context.arguments.data(using: .utf8),
           let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
            var stringDict: [String: String] = [:]
            for (key, value) in json {
                if let stringValue = value as? String {
                    stringDict[key] = stringValue
                } else {
                    stringDict[key] = String(describing: value)
                }
            }
            self.toolInput = stringDict
        } else {
            self.toolInput = [:]
        }
    }
}

// MARK: - Convenience Properties

extension PermissionRequest {

    /// The command (for Bash tool).
    public var command: String? {
        toolInput["command"]
    }

    /// The file path (for file tools).
    public var filePath: String? {
        toolInput["file_path"] ?? toolInput["path"]
    }

    /// Human-readable description of the operation.
    public var operationDescription: String {
        switch toolName {
        case "Bash", "ExecuteCommand":
            if let cmd = command {
                return "Execute: \(cmd)"
            }
            return "Execute shell command"

        case "Write":
            if let path = filePath {
                return "Write to: \(path)"
            }
            return "Write file"

        case "Edit", "MultiEdit":
            if let path = filePath {
                return "Edit: \(path)"
            }
            return "Edit file"

        case "Read":
            if let path = filePath {
                return "Read: \(path)"
            }
            return "Read file"

        case "Git":
            return "Git operation"

        default:
            return "Execute \(toolName)"
        }
    }

    /// Risk level assessment.
    public var riskLevel: RiskLevel {
        switch toolName {
        case "Read", "Glob", "Grep":
            return .low

        case "Write", "Edit", "MultiEdit":
            return .medium

        case "Bash", "ExecuteCommand":
            if let cmd = command {
                if cmd.contains("rm ") || cmd.contains("sudo") || cmd.contains("chmod") {
                    return .critical
                }
                if cmd.contains("git push") || cmd.contains("npm publish") {
                    return .high
                }
            }
            return .high

        case "Git":
            return .medium

        default:
            return .medium
        }
    }

    /// Risk level for permission requests.
    public enum RiskLevel: String, Sendable {
        case low
        case medium
        case high
        case critical
    }
}

// MARK: - Built-in Handlers

/// A handler that always allows (for testing or trusted environments).
public struct AlwaysAllowHandler: ApprovalHandler {

    public init() {}

    public func requestApproval(
        _ request: PermissionRequest,
        approvalID: String
    ) async throws -> PermissionResponse {
        .allowOnce
    }
}

/// A handler that always denies (for read-only modes).
public struct AlwaysDenyHandler: ApprovalHandler {

    public init() {}

    public func requestApproval(
        _ request: PermissionRequest,
        approvalID: String
    ) async throws -> PermissionResponse {
        .deny
    }
}

/// A CLI-based approval handler that prompts via stdin/stdout.
///
/// Displays a permission prompt and waits for user input.
///
/// ## Example Output
///
/// ```
/// === Permission Request ===
/// Tool: Bash
/// Operation: Execute: git push origin main
/// Risk Level: high
///
/// Options:
///   [y] Allow once
///   [a] Always allow this pattern
///   [n] Deny
///   [b] Deny and block pattern
///
/// Choice [y/a/n/b]:
/// ```
public struct CLIPermissionHandler: ApprovalHandler {

    private let output: @Sendable (String) -> Void

    /// Creates a CLI permission handler.
    ///
    /// - Parameter output: Function to output text (default: print).
    public init(output: @escaping @Sendable (String) -> Void = { print($0) }) {
        self.output = output
    }

    public func requestApproval(
        _ request: PermissionRequest,
        approvalID: String
    ) async throws -> PermissionResponse {
        output("")
        output("=== Permission Request ===")
        output("Tool: \(request.toolName)")
        output("Operation: \(request.operationDescription)")
        output("Risk Level: \(request.riskLevel.rawValue)")
        output("")
        output("Options:")
        output("  [y] Allow once")
        output("  [a] Always allow this pattern")
        output("  [n] Deny")
        output("  [b] Deny and block pattern")
        output("")
        output("Choice [y/a/n/b]: ")

        // Read from stdin
        guard let response = readLine()?.lowercased().trimmingCharacters(in: .whitespaces) else {
            output("No input received, denying.")
            return .deny
        }

        switch response {
        case "y", "yes":
            return .allowOnce
        case "a", "always":
            return .alwaysAllow
        case "n", "no":
            return .deny
        case "b", "block":
            return .denyAndBlock
        default:
            output("Invalid choice '\(response)', denying.")
            return .deny
        }
    }
}

/// A handler that uses a closure for custom logic.
public struct ClosurePermissionHandler: ApprovalHandler {

    private let handler: @Sendable (PermissionRequest) async throws -> PermissionResponse

    /// Creates a closure-based permission handler.
    ///
    /// - Parameter handler: The closure to handle permission requests.
    public init(handler: @escaping @Sendable (PermissionRequest) async throws -> PermissionResponse) {
        self.handler = handler
    }

    public func requestApproval(
        _ request: PermissionRequest,
        approvalID: String
    ) async throws -> PermissionResponse {
        try await handler(request)
    }
}
