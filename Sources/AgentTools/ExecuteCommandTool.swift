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
/// `ExecuteCommandTool` allows safe execution of commands through direct process
/// invocation, avoiding shell interpretation and injection vulnerabilities.
///
/// ## Features
/// - Direct process execution (no shell interpretation)
/// - Whitelist-based command validation
/// - Timeout and output size limits
///
/// ## Limitations
/// - Only whitelisted commands allowed
/// - No shell features (pipes, redirects, variables)
/// - Maximum 60 second execution time
/// - Maximum 1MB output size
public struct ExecuteCommandTool: OpenFoundationModels.Tool {
    public typealias Arguments = ExecuteCommandInput
    public typealias Output = ExecuteCommandOutput
    
    public static let name = "command_execute"
    public var name: String { Self.name }
    
    public static let description = """
    Executes commands directly without shell interpretation.
    
    Use this tool to:
    - Run system commands safely
    - Execute development tools
    - Perform file operations
    
    Features:
    - Direct process execution (no shell)
    - Whitelist-based security
    - 60 second timeout
    - 1MB output limit
    
    Limitations:
    - No shell features (pipes, redirects)
    - Only allowed commands
    - No interactive commands
    """
    
    public var description: String { Self.description }
    
    public var parameters: GenerationSchema {
        ExecuteCommandInput.generationSchema
    }
    
    // Allowed executables with their common paths
    private let allowedCommands: [String: String] = [
        // File operations
        "ls": "/bin/ls",
        "cat": "/bin/cat",
        "head": "/usr/bin/head",
        "tail": "/usr/bin/tail",
        "wc": "/usr/bin/wc",
        "sort": "/usr/bin/sort",
        "uniq": "/usr/bin/uniq",
        "find": "/usr/bin/find",
        "which": "/usr/bin/which",
        "file": "/usr/bin/file",
        "stat": "/usr/bin/stat",
        "du": "/usr/bin/du",
        "df": "/bin/df",
        
        // Text processing
        "grep": "/usr/bin/grep",
        "sed": "/usr/bin/sed",
        "awk": "/usr/bin/awk",
        
        // System info
        "pwd": "/bin/pwd",
        "whoami": "/usr/bin/whoami",
        "date": "/bin/date",
        "uname": "/usr/bin/uname",
        "ps": "/bin/ps",
        "top": "/usr/bin/top",
        "uptime": "/usr/bin/uptime",
        "free": "/usr/bin/free",
        
        // Development tools
        "git": "/usr/bin/git",
        "swift": "/usr/bin/swift",
        "python3": "/usr/bin/python3",
        "node": "/usr/local/bin/node",
        "npm": "/usr/local/bin/npm",
        "make": "/usr/bin/make",
        "cmake": "/usr/local/bin/cmake",
        "gcc": "/usr/bin/gcc",
        "clang": "/usr/bin/clang",
        
        // Network (limited)
        "ping": "/sbin/ping",
        "nslookup": "/usr/bin/nslookup",
        "dig": "/usr/bin/dig"
        // curl and wget intentionally excluded (SSRF risk)
    ]
    
    public init() {}
    
    public func call(arguments: ExecuteCommandInput) async throws -> ExecuteCommandOutput {
        // Validate command
        guard !arguments.executable.isEmpty else {
            throw FileSystemError.operationFailed(reason: "Command cannot be empty")
        }
        
        // Extract base command name
        let commandName = URL(fileURLWithPath: arguments.executable).lastPathComponent
        
        // Check if command is allowed
        guard let executablePath = allowedCommands[commandName] else {
            throw FileSystemError.operationFailed(
                reason: "Command '\(commandName)' is not allowed. Allowed commands: \(allowedCommands.keys.sorted().joined(separator: ", "))"
            )
        }
        
        // Verify executable exists
        let finalExecutablePath: String
        if FileManager.default.fileExists(atPath: executablePath) {
            finalExecutablePath = executablePath
        } else if arguments.executable.hasPrefix("/") && FileManager.default.fileExists(atPath: arguments.executable) {
            // Use provided path if it exists and command is allowed
            finalExecutablePath = arguments.executable
        } else {
            throw FileSystemError.operationFailed(
                reason: "Executable not found: \(executablePath)"
            )
        }
        
        // Parse arguments from JSON array
        let args: [String]
        if arguments.argsJson.isEmpty || arguments.argsJson == "[]" {
            args = []
        } else {
            guard let jsonData = arguments.argsJson.data(using: .utf8) else {
                throw FileSystemError.operationFailed(
                    reason: "Invalid UTF-8 in argsJson"
                )
            }
            
            do {
                args = try JSONDecoder().decode([String].self, from: jsonData)
            } catch {
                throw FileSystemError.operationFailed(
                    reason: "Invalid JSON array in argsJson. Expected format: [\"arg1\", \"arg2\"]. Error: \(error.localizedDescription)"
                )
            }
        }
        
        // Execute command
        return try await executeCommand(
            executable: finalExecutablePath,
            arguments: args
        )
    }
}

// MARK: - Input/Output Types

/// The input structure for command execution.
@Generable
public struct ExecuteCommandInput: Sendable {
    /// The command executable name or path.
    public let executable: String
    
    /// JSON array of arguments for the command.
    public let argsJson: String
}

/// Output structure for command execution operations.
public struct ExecuteCommandOutput: Sendable {
    /// Whether the command executed successfully.
    public let success: Bool
    
    /// The output from the command.
    public let output: String
    
    /// The exit status code.
    public let exitCode: Int32
    
    /// Execution time in seconds.
    public let executionTime: Double
    
    /// Whether output was truncated.
    public let truncated: Bool
    
    /// Additional metadata about the operation.
    public let metadata: [String: String]
    
    public init(
        success: Bool,
        output: String,
        exitCode: Int32,
        executionTime: Double,
        truncated: Bool,
        metadata: [String: String]
    ) {
        self.success = success
        self.output = output
        self.exitCode = exitCode
        self.executionTime = executionTime
        self.truncated = truncated
        self.metadata = metadata
    }
}

extension ExecuteCommandOutput: PromptRepresentable {
    public var promptRepresentation: Prompt {
        Prompt(description)
    }
}

extension ExecuteCommandOutput: CustomStringConvertible {
    public var description: String {
        let status = success ? "Success" : "Failed"
        let truncateNote = truncated ? " (truncated)" : ""
        
        return """
        Command Execution [\(status)]
        Exit code: \(exitCode)
        Execution time: \(String(format: "%.3f", executionTime))s\(truncateNote)
        
        Output:
        \(output)
        """
    }
}

// MARK: - Private Methods

private extension ExecuteCommandTool {
    func executeCommand(executable: String, arguments: [String]) async throws -> ExecuteCommandOutput {
        let startTime = Date()
        
        return try await withThrowingTaskGroup(of: ExecuteCommandOutput.self) { group in
            let process = Process()
            let outputPipe = Pipe()
            let errorPipe = Pipe()
            
            // Configure process
            process.executableURL = URL(fileURLWithPath: executable)
            process.arguments = arguments
            process.standardOutput = outputPipe
            process.standardError = errorPipe
            
            // Minimal, safe environment
            process.environment = [
                "PATH": "/usr/bin:/bin:/usr/local/bin",
                "HOME": NSHomeDirectory(),
                "USER": NSUserName(),
                "SHELL": "/bin/bash",
                "LANG": "en_US.UTF-8"
            ]
            
            // Add timeout task (60 seconds)
            group.addTask {
                try await Task.sleep(for: .seconds(60))
                if process.isRunning {
                    process.terminate()
                    // Wait briefly for graceful termination
                    try await Task.sleep(for: .milliseconds(500))
                    if process.isRunning {
                        process.interrupt() // SIGINT
                        try await Task.sleep(for: .milliseconds(500))
                        if process.isRunning {
                            // Force kill as last resort
                            kill(process.processIdentifier, SIGKILL)
                        }
                    }
                }
                throw FileSystemError.operationFailed(reason: "Command timed out after 60 seconds")
            }
            
            // Add execution task
            group.addTask {
                try process.run()
                process.waitUntilExit()
                
                let executionTime = Date().timeIntervalSince(startTime)
                
                // Read output with size limit (1MB)
                let maxOutputSize = 1024 * 1024
                let outputData = outputPipe.fileHandleForReading.readDataToEndOfFile()
                let errorData = errorPipe.fileHandleForReading.readDataToEndOfFile()
                
                // Combine and truncate if needed
                var combinedData = outputData
                if !errorData.isEmpty {
                    combinedData.append("\n[STDERR]\n".data(using: .utf8) ?? Data())
                    combinedData.append(errorData)
                }
                
                let truncated = combinedData.count > maxOutputSize
                if truncated {
                    combinedData = combinedData.prefix(maxOutputSize)
                }
                
                let output = String(data: combinedData, encoding: .utf8) ?? ""
                let finalOutput = truncated ? output + "\n... [Output truncated]" : output
                
                let metadata: [String: String] = [
                    "command": executable,
                    "arguments": arguments.joined(separator: " "),
                    "exit_code": String(process.terminationStatus),
                    "execution_time": String(format: "%.3f", executionTime),
                    "output_size": String(combinedData.count),
                    "truncated": String(truncated)
                ]
                
                return ExecuteCommandOutput(
                    success: process.terminationStatus == 0,
                    output: finalOutput,
                    exitCode: process.terminationStatus,
                    executionTime: executionTime,
                    truncated: truncated,
                    metadata: metadata
                )
            }
            
            // Wait for either completion or timeout
            for try await result in group {
                // Cancel remaining tasks
                group.cancelAll()
                return result
            }
            
            // Should not reach here
            throw FileSystemError.operationFailed(reason: "Unexpected execution error")
        }
    }
}

