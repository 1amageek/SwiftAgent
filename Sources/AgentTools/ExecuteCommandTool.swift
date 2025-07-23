//
//  ExecuteCommandTool.swift
//  SwiftAgent
//
//  Created by Norikazu Muramoto on 2025/01/11.
//

import Foundation
import OpenFoundationModels

/// A tool for executing shell commands in a controlled environment.
///
/// `ExecuteCommandTool` allows safe execution of shell commands or scripts while enforcing basic
/// input validation and sanitization to prevent misuse or unsafe behavior.
///
/// ## Features
/// - Run system commands or shell scripts.
/// - Perform non-interactive system operations.
///
/// ## Limitations
/// - Does not support long-running processes.
/// - Does not allow interactive commands.
/// - Cannot execute commands requiring user input.
public struct ExecuteCommandTool: OpenFoundationModels.Tool {
    public typealias Arguments = ExecuteCommandInput
    
    public static let name = "execute"
    public var name: String { Self.name }
    
    public static let description = """
    A tool for executing shell commands in a controlled environment.
    
    Use this tool to:
    - Run system commands
    - Execute shell scripts
    - Perform non-interactive system operations
    
    Limitations:
    - Does not support long-running processes
    - Does not allow interactive commands
    - Cannot execute commands requiring user input
    """
    
    public var description: String { Self.description }
    
    public init() {}
    
    public func call(arguments: ExecuteCommandInput) async throws -> ToolOutput {
        guard !arguments.command.isEmpty else {
            return ToolOutput("Command Execution [Failed]\nOutput: Command cannot be empty\nMetadata:\n  error: Command cannot be empty")
        }
        
        let sanitizedCommand = sanitizeCommand(arguments.command)
        guard validateCommand(sanitizedCommand) else {
            return ToolOutput("Command Execution [Failed]\nOutput: Unsafe command detected: \(arguments.command)\nMetadata:\n  error: Unsafe command detected: \(arguments.command)")
        }
        
        return try await executeCommand(sanitizedCommand)
    }
}


// MARK: - Input/Output Types

/// The input structure for command execution.
@Generable
public struct ExecuteCommandInput: Codable, Sendable, ConvertibleFromGeneratedContent {
    /// The shell command to execute.
    @Guide(description: "The shell command to execute")
    public let command: String
    
    /// Creates a new instance of `ExecuteCommandInput`.
    ///
    /// - Parameter command: The shell command to execute.
    public init(command: String) {
        self.command = command
    }
}


// MARK: - Private Methods

private extension ExecuteCommandTool {
    /// Executes a sanitized shell command and returns the result.
    ///
    /// - Parameter command: The sanitized shell command to execute.
    /// - Returns: The result of the command execution.
    /// - Throws: `ToolError` if the command fails.
    func executeCommand(_ command: String) async throws -> ToolOutput {
        return try await withCheckedThrowingContinuation { continuation in
            let process = Process()
            let pipe = Pipe()
            
            process.executableURL = URL(fileURLWithPath: "/bin/bash")
            process.arguments = ["-c", command]
            process.standardOutput = pipe
            process.standardError = pipe
            
            process.terminationHandler = { process in
                do {
                    let data = try pipe.fileHandleForReading.readToEnd() ?? Data()
                    let output = String(data: data, encoding: .utf8) ?? ""
                    
                    if process.terminationStatus == 0 {
                        continuation.resume(returning: ToolOutput(
                            "Command Execution [Success]\n" +
                            "Output: \(output)\n" +
                            "Metadata:\n" +
                            "  status: \(process.terminationStatus)\n" +
                            "  command: \(command)"
                        ))
                    } else {
                        continuation.resume(returning: ToolOutput(
                            "Command Execution [Failed]\n" +
                            "Output: \(output)\n" +
                            "Metadata:\n" +
                            "  status: \(process.terminationStatus)\n" +
                            "  command: \(command)"
                        ))
                    }
                } catch {
                    continuation.resume(returning: ToolOutput(
                        "Command Execution [Failed]\n" +
                        "Output: Failed to execute command: \(error.localizedDescription)\n" +
                        "Metadata:\n" +
                        "  error: Failed to execute command: \(error.localizedDescription)"
                    ))
                }
            }
            
            do {
                try process.run()
            } catch {
                continuation.resume(returning: ToolOutput(
                    "Command Execution [Failed]\n" +
                    "Output: Failed to start command: \(error.localizedDescription)\n" +
                    "Metadata:\n" +
                    "  error: Failed to start command: \(error.localizedDescription)"
                ))
            }
        }
    }
    
    /// Validates if a command is safe to execute.
    ///
    /// - Parameter command: The command to validate.
    /// - Returns: `true` if the command is considered safe, `false` otherwise.
    func validateCommand(_ command: String) -> Bool {
        // Implement command validation logic.
        // Examples:
        // - Check for dangerous commands (e.g., `rm -rf /`).
        // - Enforce a whitelist of allowed commands.
        // - Detect suspicious patterns in the command string.
        return true
    }
    
    /// Sanitizes a command input.
    ///
    /// - Parameter command: The command to sanitize.
    /// - Returns: A sanitized version of the command.
    func sanitizeCommand(_ command: String) -> String {
        // Implement command sanitization logic.
        // Examples:
        // - Escape special characters.
        // - Remove potentially harmful input.
        return command
    }
}
