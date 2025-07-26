//
//  ExecuteCommandTool.swift
//  SwiftAgent
//
//  Created by Norikazu Muramoto on 2025/01/11.
//

import Foundation
import OpenFoundationModels
import SwiftAgent

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
        return try await withThrowingTaskGroup(of: ExecuteCommandOutput.self) { group in
            let process = Process()
            let outputPipe = Pipe()
            let errorPipe = Pipe()
            
            // Configure process
            process.executableURL = URL(fileURLWithPath: "/bin/bash")
            process.arguments = ["-c", command]
            process.standardOutput = outputPipe
            process.standardError = errorPipe
            
            // Restrict environment for security
            process.environment = [
                "PATH": "/usr/bin:/bin:/usr/local/bin",
                "HOME": "/tmp",
                "USER": "agent",
                "SHELL": "/bin/bash"
            ]
            
            // Add timeout task
            group.addTask {
                try await Task.sleep(for: .seconds(60)) // 60 second timeout
                process.terminate()
                throw ToolError.executionFailed("Command timed out after 60 seconds")
            }
            
            // Add execution task
            group.addTask {
                let startTime = Date()
                
                try process.run()
                process.waitUntilExit()
                
                let executionTime = Date().timeIntervalSince(startTime)
                
                // Read output with size limit (1MB)
                let maxOutputSize = 1024 * 1024
                let outputHandle = outputPipe.fileHandleForReading
                let errorHandle = errorPipe.fileHandleForReading
                
                var outputData = outputHandle.readDataToEndOfFile()
                var errorData = errorHandle.readDataToEndOfFile()
                
                // Truncate data if too large
                if outputData.count > maxOutputSize {
                    outputData = outputData.prefix(maxOutputSize)
                }
                if errorData.count > maxOutputSize {
                    errorData = errorData.prefix(maxOutputSize)
                }
                
                // Combine stdout and stderr
                let output = String(data: outputData, encoding: .utf8) ?? ""
                let errorOutput = String(data: errorData, encoding: .utf8) ?? ""
                let combinedOutput = output + (errorOutput.isEmpty ? "" : "\n[STDERR]\n" + errorOutput)
                
                // Final truncation check
                let finalOutput = combinedOutput.count > maxOutputSize 
                    ? String(combinedOutput.prefix(maxOutputSize)) + "\n... [Output truncated]"
                    : combinedOutput
                
                let metadata: [String: String] = [
                    "status": String(process.terminationStatus),
                    "command": command,
                    "execution_time": String(format: "%.3f", executionTime),
                    "output_size": String(finalOutput.count),
                    "truncated": String(combinedOutput.count > maxOutputSize)
                ]
                
                return ExecuteCommandOutput(
                    success: process.terminationStatus == 0,
                    output: finalOutput,
                    metadata: metadata
                )
            }
            
            // Wait for either completion or timeout
            defer { group.cancelAll() }
            guard let result = try await group.next() else {
                throw ToolError.executionFailed("No result from command execution")
            }
            
            return ToolOutput(result)
        }
    }
    
    /// Validates if a command is safe to execute.
    ///
    /// - Parameter command: The command to validate.
    /// - Returns: `true` if the command is considered safe, `false` otherwise.
    func validateCommand(_ command: String) -> Bool {
        let trimmedCommand = command.trimmingCharacters(in: .whitespaces)
        
        // Check for empty commands
        guard !trimmedCommand.isEmpty else { return false }
        
        // Dangerous patterns to block
        let dangerousPatterns = [
            // File system destruction
            "rm -rf /", "rm -rf /*", "rm -rf ~", "rm -rf .*",
            "rmdir /", "delete /",
            
            // System control
            "shutdown", "reboot", "halt", "poweroff", "systemctl",
            "service ", "init ", "telinit",
            
            // Process manipulation
            "kill -9", "killall", "pkill",
            
            // Network/system access
            "sudo ", "su ", "doas ",
            
            // Fork bombs and DoS
            ":(){ :|:& };:", ":(){ :|: & }; :",
            "while true; do", "for((;;))",
            
            // File system operations
            "mkfs", "fdisk", "dd if=", "dd of=/dev/",
            "mount ", "umount ", "swapon", "swapoff",
            
            // Dangerous redirections
            "> /dev/", ">> /dev/", "< /dev/random"
        ]
        
        // Check for dangerous patterns
        let lowercaseCommand = trimmedCommand.lowercased()
        for pattern in dangerousPatterns {
            if lowercaseCommand.contains(pattern.lowercased()) {
                return false
            }
        }
        
        // Block shell operators that can chain commands or redirect
        let shellOperators = [";", "&&", "||", "|", "&", ">", "<", ">>", "<<", "`", "$("]
        for op in shellOperators {
            if trimmedCommand.contains(op) {
                return false
            }
        }
        
        // Basic whitelist approach - allow common safe commands
        let allowedCommands = [
            "echo", "cat", "ls", "pwd", "whoami", "date", "uname",
            "head", "tail", "grep", "wc", "sort", "uniq",
            "find", "which", "type", "file", "stat",
            "ps", "top", "uptime", "free", "df", "du",
            "curl", "wget", "ping", "nslookup", "dig",
            "git", "python3", "node", "npm", "swift", "java",
            "make", "cmake", "gcc", "clang"
        ]
        
        let commandParts = trimmedCommand.components(separatedBy: .whitespaces)
        guard let firstCommand = commandParts.first else { return false }
        
        // Extract base command name (remove path if present)
        let baseCommand = URL(fileURLWithPath: firstCommand).lastPathComponent
        
        return allowedCommands.contains(baseCommand)
    }
    
    /// Sanitizes a command input.
    ///
    /// - Parameter command: The command to sanitize.
    /// - Returns: A sanitized version of the command.
    func sanitizeCommand(_ command: String) -> String {
        let trimmed = command.trimmingCharacters(in: .whitespacesAndNewlines)
        
        // Replace multiple spaces with single space
        let singleSpaced = trimmed.replacingOccurrences(
            of: " +",
            with: " ",
            options: .regularExpression
        )
        
        // Remove null bytes and control characters
        let filtered = singleSpaced.filter { char in
            let scalar = char.unicodeScalars.first?.value ?? 0
            // Allow printable ASCII and space/tab
            return (scalar >= 32 && scalar < 127) || scalar == 9
        }
        
        return filtered
    }
}
