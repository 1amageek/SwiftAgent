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
/// - Configurable timeout (up to 10 minutes)
/// - Working directory specification
/// - Output size limits (1MB)
///
/// ## Usage
/// - Specify the executable name (e.g., "ls", "git", "swift")
/// - Provide arguments as a JSON array
/// - Optionally set a custom timeout (default: 120 seconds)
/// - Optionally specify working directory
///
/// ## Limitations
/// - Only whitelisted commands allowed
/// - No shell features (pipes, redirects, variables)
/// - Maximum 10 minute execution time
/// - Maximum 1MB output size
/// - No interactive commands
public struct ExecuteCommandTool: OpenFoundationModels.Tool {
    public typealias Arguments = ExecuteCommandInput
    public typealias Output = ExecuteCommandOutput

    public static let name = "bash"
    public var name: String { Self.name }

    /// Default timeout in seconds
    public static let defaultTimeout: TimeInterval = 120

    /// Maximum allowed timeout in seconds (10 minutes)
    public static let maxTimeout: TimeInterval = 600

    /// Maximum output size in bytes (1MB)
    public static let maxOutputSize = 1024 * 1024

    public static let description = """
    Execute shell command. Allowed: ls, cat, git, swift, python3, node, npm, make, etc. \
    No pipes/redirects. Max 10min timeout, 1MB output.
    """

    public var description: String { Self.description }

    public var parameters: GenerationSchema {
        ExecuteCommandInput.generationSchema
    }

    private let workingDirectory: String

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
        "mkdir": "/bin/mkdir",
        "cp": "/bin/cp",
        "mv": "/bin/mv",
        "rm": "/bin/rm",
        "touch": "/usr/bin/touch",
        "chmod": "/bin/chmod",

        // Text processing
        "grep": "/usr/bin/grep",
        "sed": "/usr/bin/sed",
        "awk": "/usr/bin/awk",
        "diff": "/usr/bin/diff",
        "tr": "/usr/bin/tr",
        "cut": "/usr/bin/cut",

        // System info
        "pwd": "/bin/pwd",
        "whoami": "/usr/bin/whoami",
        "date": "/bin/date",
        "uname": "/usr/bin/uname",
        "ps": "/bin/ps",
        "uptime": "/usr/bin/uptime",
        "env": "/usr/bin/env",
        "printenv": "/usr/bin/printenv",

        // Development tools
        "git": "/usr/bin/git",
        "swift": "/usr/bin/swift",
        "swiftc": "/usr/bin/swiftc",
        "xcodebuild": "/usr/bin/xcodebuild",
        "xcrun": "/usr/bin/xcrun",
        "python3": "/usr/bin/python3",
        "pip3": "/usr/bin/pip3",
        "node": "/usr/local/bin/node",
        "npm": "/usr/local/bin/npm",
        "npx": "/usr/local/bin/npx",
        "make": "/usr/bin/make",
        "cmake": "/usr/local/bin/cmake",
        "gcc": "/usr/bin/gcc",
        "clang": "/usr/bin/clang",
        "cargo": "/usr/local/bin/cargo",
        "rustc": "/usr/local/bin/rustc",
        "go": "/usr/local/bin/go",

        // Package managers
        "brew": "/opt/homebrew/bin/brew",

        // Network (limited)
        "ping": "/sbin/ping",
        "nslookup": "/usr/bin/nslookup",
        "dig": "/usr/bin/dig",
        "host": "/usr/bin/host"
        // curl and wget intentionally excluded (SSRF risk - use URLFetchTool)
    ]

    public init(workingDirectory: String = FileManager.default.currentDirectoryPath) {
        self.workingDirectory = workingDirectory
    }
    
    public func call(arguments: ExecuteCommandInput) async throws -> ExecuteCommandOutput {
        // Validate command
        guard !arguments.command.isEmpty else {
            throw FileSystemError.operationFailed(reason: "Command cannot be empty")
        }

        // Parse command string into executable and arguments
        let parts = parseCommand(arguments.command)
        guard !parts.isEmpty else {
            throw FileSystemError.operationFailed(reason: "Invalid command format")
        }

        let commandName = parts[0]
        let args = Array(parts.dropFirst())

        // Check if command is allowed
        guard let executablePath = allowedCommands[commandName] else {
            throw FileSystemError.operationFailed(
                reason: "Command '\(commandName)' is not allowed. Allowed commands: \(allowedCommands.keys.sorted().joined(separator: ", "))"
            )
        }

        // Verify executable exists - check multiple possible paths
        let possiblePaths = [
            executablePath,
            "/usr/bin/\(commandName)",
            "/bin/\(commandName)",
            "/usr/local/bin/\(commandName)",
            "/opt/homebrew/bin/\(commandName)"
        ]

        var finalExecutablePath: String?
        for path in possiblePaths {
            if FileManager.default.fileExists(atPath: path) {
                finalExecutablePath = path
                break
            }
        }

        guard let execPath = finalExecutablePath else {
            throw FileSystemError.operationFailed(
                reason: "Executable not found: \(commandName). Checked paths: \(possiblePaths.joined(separator: ", "))"
            )
        }

        // Calculate timeout (convert from milliseconds to seconds, with bounds)
        let timeoutMs = arguments.timeout > 0 ? arguments.timeout : Int(Self.defaultTimeout * 1000)
        let timeoutSeconds = min(Double(timeoutMs) / 1000.0, Self.maxTimeout)

        // Determine working directory
        let execWorkingDir = arguments.working_dir.isEmpty ? workingDirectory : arguments.working_dir

        // Execute command
        return try await executeCommand(
            executable: execPath,
            arguments: args,
            workingDirectory: execWorkingDir,
            timeout: timeoutSeconds,
            description: arguments.command
        )
    }

    /// Parse command string into parts, handling quoted strings
    private func parseCommand(_ command: String) -> [String] {
        var parts: [String] = []
        var current = ""
        var inQuote = false
        var quoteChar: Character = "\""

        for char in command {
            if inQuote {
                if char == quoteChar {
                    inQuote = false
                } else {
                    current.append(char)
                }
            } else {
                if char == "\"" || char == "'" {
                    inQuote = true
                    quoteChar = char
                } else if char.isWhitespace {
                    if !current.isEmpty {
                        parts.append(current)
                        current = ""
                    }
                } else {
                    current.append(char)
                }
            }
        }

        if !current.isEmpty {
            parts.append(current)
        }

        return parts
    }
}

// MARK: - Input/Output Types

/// The input structure for command execution.
@Generable
public struct ExecuteCommandInput: Sendable {
    @Guide(description: "Shell command to execute (e.g., \"ls -la\", \"git status\")")
    public let command: String

    @Guide(description: "Timeout in milliseconds (default: 120000, max: 600000)")
    public let timeout: Int

    @Guide(description: "Working directory (default: current dir)")
    public let working_dir: String
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
    func executeCommand(
        executable: String,
        arguments: [String],
        workingDirectory: String,
        timeout: TimeInterval,
        description: String
    ) async throws -> ExecuteCommandOutput {
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
            process.currentDirectoryURL = URL(fileURLWithPath: workingDirectory)

            // Minimal, safe environment
            process.environment = [
                "PATH": "/usr/bin:/bin:/usr/local/bin:/opt/homebrew/bin",
                "HOME": NSHomeDirectory(),
                "USER": NSUserName(),
                "SHELL": "/bin/bash",
                "LANG": "en_US.UTF-8",
                "LC_ALL": "en_US.UTF-8"
            ]

            // Add timeout task
            group.addTask {
                try await Task.sleep(for: .seconds(timeout))
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
                throw FileSystemError.operationFailed(reason: "Command timed out after \(Int(timeout)) seconds")
            }

            // Add execution task
            group.addTask {
                try process.run()
                process.waitUntilExit()

                let executionTime = Date().timeIntervalSince(startTime)

                // Read output with size limit
                let maxOutputSize = ExecuteCommandTool.maxOutputSize
                let outputData = outputPipe.fileHandleForReading.readDataToEndOfFile()
                let errorData = errorPipe.fileHandleForReading.readDataToEndOfFile()

                // Combine and truncate if needed
                var combinedData = outputData
                if !errorData.isEmpty && process.terminationStatus != 0 {
                    combinedData.append("\n[STDERR]\n".data(using: .utf8) ?? Data())
                    combinedData.append(errorData)
                }

                let truncated = combinedData.count > maxOutputSize
                if truncated {
                    // Truncate from the middle to preserve beginning and end
                    let keepSize = maxOutputSize / 2
                    let prefix = combinedData.prefix(keepSize)
                    let suffix = combinedData.suffix(keepSize)
                    combinedData = prefix + "\n... [Output truncated - \(combinedData.count - maxOutputSize) bytes removed] ...\n".data(using: .utf8)! + suffix
                }

                let output = String(data: combinedData, encoding: .utf8) ?? ""

                let metadata: [String: String] = [
                    "command": executable,
                    "arguments": arguments.joined(separator: " "),
                    "working_directory": workingDirectory,
                    "exit_code": String(process.terminationStatus),
                    "execution_time": String(format: "%.3f", executionTime),
                    "output_size": String(combinedData.count),
                    "truncated": String(truncated),
                    "description": description
                ]

                return ExecuteCommandOutput(
                    success: process.terminationStatus == 0,
                    output: output,
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

