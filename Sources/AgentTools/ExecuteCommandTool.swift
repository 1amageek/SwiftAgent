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
            let output = ExecuteCommandOutput(
                success: false,
                output: "Command cannot be empty",
                metadata: ["error": "Command cannot be empty"]
            )
            return ToolOutput(output)
        }
        
        let sanitizedCommand = sanitizeCommand(arguments.command)
        guard validateCommand(sanitizedCommand) else {
            let output = ExecuteCommandOutput(
                success: false,
                output: "Unsafe command detected: \(arguments.command)",
                metadata: ["error": "Unsafe command detected: \(arguments.command)"]
            )
            return ToolOutput(output)
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

/// Output structure for command execution operations.
public struct ExecuteCommandOutput: Codable, Sendable, CustomStringConvertible {
    /// Whether the command executed successfully.
    public let success: Bool
    
    /// The output from the command.
    public let output: String
    
    /// Additional metadata about the operation.
    public let metadata: [String: String]
    
    /// Creates a new instance of `ExecuteCommandOutput`.
    ///
    /// - Parameters:
    ///   - success: Whether the command succeeded.
    ///   - output: The command output.
    ///   - metadata: Additional metadata.
    public init(success: Bool, output: String, metadata: [String: String]) {
        self.success = success
        self.output = output
        self.metadata = metadata
    }
    
    public var description: String {
        let status = success ? "Success" : "Failed"
        let metadataString = metadata.isEmpty ? "" : "\nMetadata:\n" + metadata.map { "  \($0.key): \($0.value)" }.joined(separator: "\n")
        
        return """
        Command Execution [\(status)]
        Output: \(output)\(metadataString)
        """
    }
}

// Make ExecuteCommandOutput conform to PromptRepresentable for compatibility
extension ExecuteCommandOutput: PromptRepresentable {
    public var promptRepresentation: Prompt {
        return Prompt(segments: [Prompt.Segment(text: description)])
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
                        let result = ExecuteCommandOutput(
                            success: true,
                            output: output,
                            metadata: [
                                "status": String(process.terminationStatus),
                                "command": command
                            ]
                        )
                        continuation.resume(returning: ToolOutput(result))
                    } else {
                        let result = ExecuteCommandOutput(
                            success: false,
                            output: output,
                            metadata: [
                                "status": String(process.terminationStatus),
                                "command": command
                            ]
                        )
                        continuation.resume(returning: ToolOutput(result))
                    }
                } catch {
                    let result = ExecuteCommandOutput(
                        success: false,
                        output: "Failed to execute command: \(error.localizedDescription)",
                        metadata: ["error": "Failed to execute command: \(error.localizedDescription)"]
                    )
                    continuation.resume(returning: ToolOutput(result))
                }
            }
            
            do {
                try process.run()
            } catch {
                let result = ExecuteCommandOutput(
                    success: false,
                    output: "Failed to start command: \(error.localizedDescription)",
                    metadata: ["error": "Failed to start command: \(error.localizedDescription)"]
                )
                continuation.resume(returning: ToolOutput(result))
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
