import Foundation
import OpenFoundationModels
import SwiftAgent

/// A tool for executing Git commands safely.
///
/// `GitTool` provides a controlled interface for executing Git commands while ensuring
/// basic validation and safety checks.
public struct GitTool: OpenFoundationModels.Tool {
    public typealias Arguments = GitInput
    
    public static let name = "git_control"
    public var name: String { Self.name }
    
    public static let description = """
    A tool for executing Git commands safely within a repository.
    
    Use this tool to:
    - Execute basic Git operations
    - Manage repository state
    - Access Git information
    
    Limitations:
    - Complex Git operations requiring interaction are not supported
    - Some Git commands may be restricted for safety
    """
    
    public var description: String { Self.description }
    
    private let gitPath: String
    
    public init(gitPath: String = "/usr/bin/git") {
        self.gitPath = gitPath
    }
    
    public func call(arguments: GitInput) async throws -> ToolOutput {
        // Validate repository path if specified
        if !arguments.repository.isEmpty {
            guard FileManager.default.fileExists(atPath: arguments.repository) else {
                let output = GitOutput(
                    success: false,
                    output: "Repository not found: \(arguments.repository)",
                    exitCode: -1,
                    metadata: ["error": "Repository not found"]
                )
                return ToolOutput(output)
            }
            
            let gitDir = URL(fileURLWithPath: arguments.repository).appendingPathComponent(".git").path
            guard FileManager.default.fileExists(atPath: gitDir) else {
                let output = GitOutput(
                    success: false,
                    output: "Not a Git repository: \(arguments.repository)",
                    exitCode: -1,
                    metadata: ["error": "Not a Git repository"]
                )
                return ToolOutput(output)
            }
        }
        
        // Validate Git command
        guard isValidGitCommand(arguments.command) else {
            let output = GitOutput(
                success: false,
                output: "Invalid or unsafe Git command: \(arguments.command)",
                exitCode: -1,
                metadata: ["error": "Invalid Git command"]
            )
            return ToolOutput(output)
        }
        
        // Execute Git command
        let result = await executeGitCommand(arguments)
        return ToolOutput(result)
    }
    
    private func isValidGitCommand(_ command: String) -> Bool {
        let allowedCommands = [
            "status", "log", "diff", "add", "commit", "push", "pull",
            "branch", "checkout", "merge", "fetch", "remote", "tag",
            "reset", "revert", "stash", "show", "clone", "init"
        ]
        return allowedCommands.contains(command)
    }
    
    private func executeGitCommand(_ input: GitInput) async -> GitOutput {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: gitPath)
        
        var arguments = [input.command]
        if !input.args.isEmpty {
            arguments.append(contentsOf: input.args.split(separator: " ").map(String.init))
        }
        process.arguments = arguments
        
        if !input.repository.isEmpty {
            process.currentDirectoryURL = URL(fileURLWithPath: input.repository)
        }
        
        let pipe = Pipe()
        let errorPipe = Pipe()
        process.standardOutput = pipe
        process.standardError = errorPipe
        
        do {
            try process.run()
            process.waitUntilExit()
            
            let outputData = pipe.fileHandleForReading.readDataToEndOfFile()
            let errorData = errorPipe.fileHandleForReading.readDataToEndOfFile()
            
            let output = String(data: outputData, encoding: .utf8) ?? ""
            let error = String(data: errorData, encoding: .utf8) ?? ""
            
            let exitCode = process.terminationStatus
            let success = exitCode == 0
            
            return GitOutput(
                success: success,
                output: success ? output : error,
                exitCode: Int(exitCode),
                metadata: [
                    "command": input.command,
                    "repository": input.repository.isEmpty ? "current directory" : input.repository,
                    "exit_code": String(exitCode)
                ]
            )
        } catch {
            return GitOutput(
                success: false,
                output: "Failed to execute Git command: \(error.localizedDescription)",
                exitCode: -1,
                metadata: [
                    "command": input.command,
                    "error": error.localizedDescription
                ]
            )
        }
    }
}

/// Input structure for Git operations.
@Generable
public struct GitInput: Codable, Sendable, ConvertibleFromGeneratedContent {
    /// The Git command to execute.
    @Guide(description: "The Git command to execute", .enumeration(["status", "log", "diff", "add", "commit", "push", "pull", "branch", "checkout", "merge", "fetch", "remote", "tag", "reset", "revert", "stash", "show", "clone", "init"]))
    public let command: String
    
    /// Path to the Git repository (empty string means current directory).
    @Guide(description: "Path to the Git repository (empty string means current directory)")
    public let repository: String
    
    /// Additional arguments for the Git command (space-separated, empty string if none).
    @Guide(description: "Additional arguments for the Git command (space-separated, empty string if none)")
    public let args: String
}

/// Output structure for Git operations.
public struct GitOutput: Codable, Sendable, CustomStringConvertible {
    /// Whether the Git command executed successfully.
    public let success: Bool
    
    /// The output from the Git command.
    public let output: String
    
    /// The exit code from the Git process.
    public let exitCode: Int
    
    /// Additional metadata about the operation.
    public let metadata: [String: String]
    
    /// Creates a new instance of `GitOutput`.
    ///
    /// - Parameters:
    ///   - success: Whether the command succeeded.
    ///   - output: The command output.
    ///   - exitCode: The process exit code.
    ///   - metadata: Additional metadata.
    public init(success: Bool, output: String, exitCode: Int, metadata: [String: String]) {
        self.success = success
        self.output = output
        self.exitCode = exitCode
        self.metadata = metadata
    }
    
    public var description: String {
        let status = success ? "Success" : "Failed"
        let metadataString = metadata.isEmpty ? "" : "\nMetadata:\n" + metadata.map { "  \($0.key): \($0.value)" }.joined(separator: "\n")
        
        return """
        Git Operation [\(status)]
        Output: \(output)\(metadataString)
        """
    }
}

// Make GitOutput conform to PromptRepresentable for compatibility
extension GitOutput: PromptRepresentable {
    public var promptRepresentation: Prompt {
        return Prompt(segments: [Prompt.Segment(text: description)])
    }
}