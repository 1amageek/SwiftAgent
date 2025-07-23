import Foundation
import OpenFoundationModels

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
        // Validate repository path
        if let repo = arguments.repository {
            guard FileManager.default.fileExists(atPath: repo) else {
                return ToolOutput("Git Operation [Failed]\nOutput: Repository not found: \(repo)\nMetadata:\n  error: Repository not found")
            }
            
            let gitDir = URL(fileURLWithPath: repo).appendingPathComponent(".git").path
            guard FileManager.default.fileExists(atPath: gitDir) else {
                return ToolOutput("Git Operation [Failed]\nOutput: Not a Git repository: \(repo)\nMetadata:\n  error: Not a Git repository")
            }
        }
        
        // Validate Git command
        guard isValidGitCommand(arguments.command) else {
            return ToolOutput("Git Operation [Failed]\nOutput: Invalid or unsafe Git command: \(arguments.command)\nMetadata:\n  error: Invalid Git command")
        }
        
        // Execute Git command
        let result = await executeGitCommand(arguments)
        return ToolOutput(result.description)
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
        if let args = input.args {
            arguments.append(contentsOf: args.split(separator: " ").map(String.init))
        }
        process.arguments = arguments
        
        if let repository = input.repository {
            process.currentDirectoryURL = URL(fileURLWithPath: repository)
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
                    "repository": input.repository ?? "current directory",
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
    
    /// Optional path to the Git repository.
    @Guide(description: "Optional path to the Git repository")
    public let repository: String?
    
    /// Additional arguments for the Git command (space-separated).
    @Guide(description: "Additional arguments for the Git command (space-separated)")
    public let args: String?
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