//
//  FileSystemTool.swift
//  SwiftAgent
//
//  Created by Norikazu Muramoto on 2025/01/13.
//

import Foundation
import OpenFoundationModels

/// A tool for performing file system operations safely within a controlled working directory.
///
/// `FileSystemTool` allows controlled access to read, write, and list files or directories
/// while enforcing path safety to prevent access outside the specified working directory.
///
/// ## Features
/// - Read file contents as UTF-8 text
/// - Write text data to files
/// - List directory contents
///
/// ## Limitations
/// - Operates only within the configured working directory
/// - Does not support binary file operations
/// - Does not allow modifications to system files
public struct FileSystemTool: OpenFoundationModels.Tool {
    public typealias Arguments = FileSystemInput
    
    public static let name = "filesystem"
    public var name: String { Self.name }
    
    public static let description = """
    A tool for performing file system operations within a controlled working directory.
    
    Use this tool to:
    - Read file contents as UTF-8 text
    - Write text data to files
    - List directory contents
    
    Limitations:
    - Operates only within the configured working directory
    - Does not support binary file operations
    - Does not allow modifications to system files
    """
    
    public var description: String { Self.description }
    
    private let workingDirectory: String
    private let fsActor: FileSystemActor
    
    public init(workingDirectory: String) {
        self.workingDirectory = workingDirectory
        self.fsActor = FileSystemActor()
    }
    
    public func call(arguments: FileSystemInput) async throws -> ToolOutput {
        let normalizedPath = normalizePath(arguments.path)
        guard isPathSafe(normalizedPath) else {
            return ToolOutput("FileSystem Operation [Failed]\nContent: Path is not within working directory: \(arguments.path)\nMetadata:\n  operation: \(arguments.operation)\n  error: Path is not within working directory: \(arguments.path)")
        }
        
        switch arguments.operation {
        case "read":
            let result = try await readFile(at: normalizedPath)
            return ToolOutput(result.description)
        case "write":
            guard let content = arguments.content else {
                return ToolOutput("FileSystem Operation [Failed]\nContent: Missing content for write operation\nMetadata:\n  operation: \(arguments.operation)\n  error: Missing content for write operation")
            }
            let result = try await writeFile(content: content, to: normalizedPath)
            return ToolOutput(result.description)
        default:
            return ToolOutput("FileSystem Operation [Failed]\nContent: Invalid operation: \(arguments.operation)\nMetadata:\n  error: Invalid operation")  
        }
    }
}

// MARK: - Input/Output Types

/// The input structure for file system operations.
@Generable
public struct FileSystemInput: Codable, Sendable, ConvertibleFromGeneratedContent {
    /// The operation to perform (e.g., read, write, or list).
    @Guide(description: "The operation to perform", .enumeration(["read", "write"]))
    public let operation: String
    
    /// The path to the file or directory.
    @Guide(description: "Path to the file or directory")
    public let path: String
    
    /// The content to write (used only for `write` operations).
    @Guide(description: "Content to write (for write operation only)")
    public let content: String?
}

/// The output structure for file system operations.
public struct FileSystemOutput: Codable, Sendable, CustomStringConvertible {
    /// Whether the operation was successful.
    public let success: Bool
    
    /// The content produced by the operation (e.g., file contents or directory listing).
    public let content: String
    
    /// Additional metadata about the operation.
    public let metadata: [String: String]
    
    /// Creates a new instance of `FileSystemOutput`.
    ///
    /// - Parameters:
    ///   - success: Indicates if the operation succeeded.
    ///   - content: The content resulting from the operation.
    ///   - metadata: Additional information about the operation.
    public init(success: Bool, content: String, metadata: [String: String]) {
        self.success = success
        self.content = content
        self.metadata = metadata
    }
    
    public var description: String {
        let status = success ? "Success" : "Failed"
        let metadataString = metadata.isEmpty ? "" : "\nMetadata:\n" + metadata.map { "  \($0.key): \($0.value)" }.joined(separator: "\n")
        
        return """
        FileSystem Operation [\(status)]
        Content: \(content)\(metadataString)
        """
    }
}

// MARK: - Private File Operations

private extension FileSystemTool {
    func readFile(at path: String) async throws -> FileSystemOutput {
        guard await fsActor.fileExists(atPath: path) else {
            return FileSystemOutput(
                success: false,
                content: "File not found: \(path)",
                metadata: [
                    "operation": "read",
                    "error": "File not found: \(path)"
                ]
            )
        }
        
        do {
            let data = try Data(contentsOf: URL(fileURLWithPath: path))
            guard let content = String(data: data, encoding: .utf8) else {
                return FileSystemOutput(
                    success: false,
                    content: "Could not read file as UTF-8 text",
                    metadata: [
                        "operation": "read",
                        "error": "Could not read file as UTF-8 text"
                    ]
                )
            }
            
            return FileSystemOutput(
                success: true,
                content: content,
                metadata: [
                    "operation": "read",
                    "path": path,
                    "size": "\(data.count)"
                ]
            )
        } catch {
            return FileSystemOutput(
                success: false,
                content: "Error reading file: \(error.localizedDescription)",
                metadata: [
                    "operation": "read",
                    "error": error.localizedDescription
                ]
            )
        }
    }
    
    func writeFile(content: String, to path: String) async throws -> FileSystemOutput {
        let url = URL(fileURLWithPath: path)
        
        // Create directory if needed
        let directory = url.deletingLastPathComponent().path
        if !directory.isEmpty {
            try await fsActor.createDirectory(atPath: directory)
        }
        
        do {
            let data = content.data(using: .utf8) ?? Data()
            try data.write(to: url)
            
            return FileSystemOutput(
                success: true,
                content: "File written successfully",
                metadata: [
                    "operation": "write",
                    "path": path,
                    "size": "\(data.count)"
                ]
            )
        } catch {
            return FileSystemOutput(
                success: false,
                content: "Error writing file: \(error.localizedDescription)",
                metadata: [
                    "operation": "write",
                    "error": error.localizedDescription
                ]
            )
        }
    }
    
    func normalizePath(_ path: String) -> String {
        let expandedPath = NSString(string: path).expandingTildeInPath
        let absolutePath: String
        
        if expandedPath.hasPrefix("/") {
            absolutePath = expandedPath
        } else {
            absolutePath = URL(fileURLWithPath: workingDirectory).appendingPathComponent(expandedPath).path
        }
        
        return URL(fileURLWithPath: absolutePath).standardized.path
    }
    
    func isPathSafe(_ path: String) -> Bool {
        let normalizedPath = URL(fileURLWithPath: path).standardized.path
        let normalizedWorkingDir = URL(fileURLWithPath: workingDirectory).standardized.path
        
        return normalizedPath.hasPrefix(normalizedWorkingDir)
    }
}

// MARK: - FileSystemActor

/// An actor to ensure thread-safe file system operations.
private actor FileSystemActor {
    func fileExists(atPath path: String) -> Bool {
        FileManager.default.fileExists(atPath: path)
    }
    
    func createDirectory(atPath path: String) throws {
        try FileManager.default.createDirectory(atPath: path, withIntermediateDirectories: true, attributes: nil)
    }
}