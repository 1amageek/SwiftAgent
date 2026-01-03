//
//  GitTool.swift
//  SwiftAgent
//
//  Created by Norikazu Muramoto on 2025/01/13.
//

import Foundation
import SwiftAgent

/// A tool for executing Git commands in a repository.
///
/// `GitTool` provides controlled Git operations with safety checks
/// to prevent destructive actions without explicit permission.
///
/// ## Features
/// - Safe Git command execution
/// - Destructive operation protection
/// - Repository validation
/// - Timeout and output limits
///
/// ## Limitations
/// - Only whitelisted Git subcommands
/// - Destructive operations require explicit permission
/// - Maximum 60 second execution time
/// - Maximum 1MB output size
public struct GitTool: Tool {
    public typealias Arguments = GitInput
    public typealias Output = GitOutput

    public static let name = "git"
    public var name: String { Self.name }

    public static let description = """
    Execute Git commands. Safe read operations by default. \
    Destructive operations require allow_mutating=true. Max 60s, 1MB output.
    """

    public var description: String { Self.description }
    
    public var parameters: GenerationSchema {
        GitInput.generationSchema
    }
    
    private let gitPath: String
    
    // Read-only Git commands (safe by default)
    private let readOnlyCommands: Set<String> = [
        "status", "log", "diff", "show", "branch", "tag",
        "ls-files", "ls-tree", "cat-file", "rev-parse",
        "describe", "shortlog", "blame", "grep",
        "remote", "submodule", "worktree"
    ]
    
    // Mutating Git commands (require explicit permission)
    private let mutatingCommands: Set<String> = [
        "add", "commit", "push", "pull", "fetch", "merge",
        "rebase", "reset", "revert", "checkout", "switch",
        "restore", "rm", "mv", "clean", "stash",
        "cherry-pick", "am", "apply", "init", "clone"
    ]
    
    public init(gitPath: String = "/usr/bin/git") {
        self.gitPath = gitPath
    }
    
    public func call(arguments: GitInput) async throws -> GitOutput {
        // Validate Git command
        let command = arguments.command.trimmingCharacters(in: .whitespaces)
        guard !command.isEmpty else {
            throw FileSystemError.operationFailed(reason: "Git command cannot be empty")
        }
        
        // Check if command is allowed
        let isReadOnly = readOnlyCommands.contains(command)
        let isMutating = mutatingCommands.contains(command)
        
        guard isReadOnly || isMutating else {
            throw FileSystemError.operationFailed(
                reason: "Git command '\(command)' is not allowed. Allowed commands: \(Array(readOnlyCommands.union(mutatingCommands)).sorted().joined(separator: ", "))"
            )
        }
        
        // Check permission for mutating commands
        if isMutating {
            switch arguments.allowMutating.lowercased() {
            case "true":
                break // Permission granted
            case "false", "":
                throw FileSystemError.operationFailed(
                    reason: "Mutating Git command '\(command)' requires allowMutating='true'"
                )
            default:
                throw FileSystemError.operationFailed(
                    reason: "allowMutating must be 'true' or 'false', got: '\(arguments.allowMutating)'"
                )
            }
        }
        
        // Validate repository path if specified
        let workingDirectory: String
        if !arguments.repository.isEmpty {
            guard FileManager.default.fileExists(atPath: arguments.repository) else {
                throw FileSystemError.fileNotFound(path: arguments.repository)
            }
            
            let gitDir = URL(fileURLWithPath: arguments.repository).appendingPathComponent(".git")
            guard FileManager.default.fileExists(atPath: gitDir.path) else {
                throw FileSystemError.operationFailed(
                    reason: "Not a Git repository: \(arguments.repository)"
                )
            }
            workingDirectory = arguments.repository
        } else {
            workingDirectory = FileManager.default.currentDirectoryPath
            
            // Check if current directory is a Git repository
            let gitDir = URL(fileURLWithPath: workingDirectory).appendingPathComponent(".git")
            guard FileManager.default.fileExists(atPath: gitDir.path) else {
                throw FileSystemError.operationFailed(
                    reason: "Not a Git repository: \(workingDirectory)"
                )
            }
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
        
        // Execute Git command
        return try await executeGitCommand(
            command: command,
            arguments: args,
            workingDirectory: workingDirectory
        )
    }
    
    private func executeGitCommand(command: String, arguments: [String], workingDirectory: String) async throws -> GitOutput {
        let startTime = Date()
        
        return try await withThrowingTaskGroup(of: GitOutput.self) { group in
            let process = Process()
            let outputPipe = Pipe()
            let errorPipe = Pipe()
            
            // Configure process
            process.executableURL = URL(fileURLWithPath: gitPath)
            process.arguments = [command] + arguments
            process.standardOutput = outputPipe
            process.standardError = errorPipe
            process.currentDirectoryURL = URL(fileURLWithPath: workingDirectory)
            
            // Git-specific environment
            process.environment = [
                "PATH": "/usr/bin:/bin:/usr/local/bin",
                "HOME": NSHomeDirectory(),
                "USER": NSUserName(),
                "GIT_TERMINAL_PROMPT": "0", // Disable prompts
                "GIT_ASKPASS": "echo", // Prevent password prompts
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
                        // Force kill
                        kill(process.processIdentifier, SIGKILL)
                    }
                }
                throw FileSystemError.operationFailed(reason: "Git command timed out after 60 seconds")
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
                
                // Combine stdout and stderr
                var combinedData = outputData
                if !errorData.isEmpty && process.terminationStatus != 0 {
                    // Only include stderr for failures
                    combinedData.append("\n[STDERR]\n".data(using: .utf8) ?? Data())
                    combinedData.append(errorData)
                }
                
                // Truncate if needed
                let truncated = combinedData.count > maxOutputSize
                if truncated {
                    combinedData = combinedData.prefix(maxOutputSize)
                }
                
                let output = String(data: combinedData, encoding: .utf8) ?? ""
                let finalOutput = truncated ? output + "\n... [Output truncated]" : output
                
                let metadata: [String: String] = [
                    "command": "git \(command) \(arguments.joined(separator: " "))",
                    "repository": workingDirectory,
                    "exit_code": String(process.terminationStatus),
                    "execution_time": String(format: "%.3f", executionTime),
                    "output_size": String(combinedData.count),
                    "truncated": String(truncated)
                ]
                
                return GitOutput(
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
            throw FileSystemError.operationFailed(reason: "Unexpected Git execution error")
        }
    }
}

// MARK: - Input/Output Types

/// Input structure for Git operations.
@Generable
public struct GitInput: Sendable {
    /// The Git subcommand to execute.
    public let command: String
    
    /// Path to the Git repository (empty string means current directory).
    public let repository: String
    
    /// JSON array of arguments for the Git command.
    public let argsJson: String
    
    /// Whether to allow mutating operations.
    public let allowMutating: String
}

/// Output structure for Git operations.
public struct GitOutput: Sendable {
    /// Whether the command executed successfully.
    public let success: Bool
    
    /// The output from the Git command.
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

extension GitOutput: PromptRepresentable {
    public var promptRepresentation: Prompt {
        Prompt(description)
    }
}

extension GitOutput: CustomStringConvertible {
    public var description: String {
        let status = success ? "Success" : "Failed"
        let truncateNote = truncated ? " (truncated)" : ""
        
        return """
        Git Operation [\(status)]
        Exit code: \(exitCode)
        Execution time: \(String(format: "%.3f", executionTime))s\(truncateNote)
        
        Output:
        \(output)
        """
    }
}

