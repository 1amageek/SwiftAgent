//
//  FileSystemTool.swift
//  SwiftAgent
//
//  Created by Norikazu Muramoto on 2025/01/13.
//

import Foundation
import OpenFoundationModels
import SwiftAgent

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
    public typealias Output = FileSystemOutput
    
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
    
    public func call(arguments: FileSystemInput) async throws -> FileSystemOutput {
        let normalizedPath = normalizePath(arguments.path)
        guard isPathSafe(normalizedPath) else {
            let output = FileSystemOutput(
                success: false,
                content: "Path is not within working directory: \(arguments.path)",
                metadata: [
                    "operation": arguments.operation,
                    "error": "Path is not within working directory: \(arguments.path)"
                ]
            )
            return output
        }
        
        switch arguments.operation {
        case "read":
            let result = try await readFile(at: normalizedPath)
            return result
        case "write":
            if arguments.content.isEmpty {
                let output = FileSystemOutput(
                    success: false,
                    content: "Missing content for write operation",
                    metadata: [
                        "operation": arguments.operation,
                        "error": "Missing content for write operation"
                    ]
                )
                return output
            }
            let result = try await writeFile(content: arguments.content, to: normalizedPath)
            return result
        case "list":
            let result = try await listDirectory(at: normalizedPath)
            return result
        default:
            let output = FileSystemOutput(
                success: false,
                content: "Invalid operation: \(arguments.operation). Valid operations: read, write, list",
                metadata: ["error": "Invalid operation"]
            )
            return output  
        }
    }
}

// MARK: - Input/Output Types

/// The input structure for file system operations.
@Generable
public struct FileSystemInput: Codable, Sendable, ConvertibleFromGeneratedContent {
    /// The operation to perform (e.g., read, write, or list).
    @Guide(description: "The operation to perform", .enumeration(["read", "write", "list"]))
    public let operation: String
    
    /// The path to the file or directory.
    @Guide(description: "Path to the file or directory")
    public let path: String
    
    /// The content to write (used only for `write` operations, empty string if not applicable).
    @Guide(description: "Content to write (for write operation only, empty string if not applicable)")
    public let content: String
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
            // Check file size before reading
            let fileURL = URL(fileURLWithPath: path)
            let attributes = try FileManager.default.attributesOfItem(atPath: path)
            let fileSize = attributes[.size] as? Int64 ?? 0
            let maxFileSize: Int64 = 1024 * 1024 // 1MB limit
            
            if fileSize > maxFileSize {
                return FileSystemOutput(
                    success: false,
                    content: "File too large: \(fileSize) bytes (limit: \(maxFileSize) bytes)",
                    metadata: [
                        "operation": "read",
                        "error": "File size exceeds limit",
                        "file_size": String(fileSize),
                        "size_limit": String(maxFileSize)
                    ]
                )
            }
            
            let data = try Data(contentsOf: fileURL)
            guard let content = String(data: data, encoding: .utf8) else {
                // Try to determine if it's a binary file
                let isBinary = data.prefix(1024).contains { $0 == 0 || ($0 < 32 && $0 != 9 && $0 != 10 && $0 != 13) }
                if isBinary {
                    return FileSystemOutput(
                        success: false,
                        content: "Cannot read binary file as text",
                        metadata: [
                            "operation": "read",
                            "error": "Binary file detected",
                            "size": String(data.count)
                        ]
                    )
                } else {
                    return FileSystemOutput(
                        success: false,
                        content: "Could not read file as UTF-8 text",
                        metadata: [
                            "operation": "read",
                            "error": "Invalid UTF-8 encoding",
                            "size": String(data.count)
                        ]
                    )
                }
            }
            
            return FileSystemOutput(
                success: true,
                content: content,
                metadata: [
                    "operation": "read",
                    "path": path,
                    "size": String(data.count),
                    "encoding": "utf8"
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
    
    func listDirectory(at path: String) async throws -> FileSystemOutput {
        // Check if path is a directory
        var isDirectory: ObjCBool = false
        guard await fsActor.fileExists(atPath: path, isDirectory: &isDirectory) else {
            return FileSystemOutput(
                success: false,
                content: "Directory not found: \(path)",
                metadata: [
                    "operation": "list",
                    "error": "Directory not found: \(path)"
                ]
            )
        }
        
        guard isDirectory.boolValue else {
            return FileSystemOutput(
                success: false,
                content: "Path is not a directory: \(path)",
                metadata: [
                    "operation": "list",
                    "error": "Path is not a directory: \(path)"
                ]
            )
        }
        
        do {
            let items = try await fsActor.listDirectory(atPath: path)
            let sortedItems = items.sorted()
            
            // Create detailed listing with file info
            var detailedListing: [String] = []
            for item in sortedItems {
                let itemPath = URL(fileURLWithPath: path).appendingPathComponent(item).path
                let itemInfo = await fsActor.getFileInfo(atPath: itemPath)
                detailedListing.append(itemInfo)
            }
            
            return FileSystemOutput(
                success: true,
                content: detailedListing.joined(separator: "\n"),
                metadata: [
                    "operation": "list",
                    "path": path,
                    "item_count": String(items.count)
                ]
            )
        } catch {
            return FileSystemOutput(
                success: false,
                content: "Error listing directory: \(error.localizedDescription)",
                metadata: [
                    "operation": "list",
                    "error": error.localizedDescription
                ]
            )
        }
    }
    
    func writeFile(content: String, to path: String) async throws -> FileSystemOutput {
        // Check content size limit
        let data = content.data(using: .utf8) ?? Data()
        let maxFileSize: Int = 1024 * 1024 // 1MB limit
        
        if data.count > maxFileSize {
            return FileSystemOutput(
                success: false,
                content: "Content too large: \(data.count) bytes (limit: \(maxFileSize) bytes)",
                metadata: [
                    "operation": "write",
                    "error": "Content size exceeds limit",
                    "content_size": String(data.count),
                    "size_limit": String(maxFileSize)
                ]
            )
        }
        
        let url = URL(fileURLWithPath: path)
        
        // Create directory if needed
        let directory = url.deletingLastPathComponent().path
        if !directory.isEmpty {
            try await fsActor.createDirectory(atPath: directory)
        }
        
        do {
            // Use atomic write option for safety
            try data.write(to: url, options: .atomic)
            
            return FileSystemOutput(
                success: true,
                content: "File written successfully",
                metadata: [
                    "operation": "write",
                    "path": path,
                    "size": String(data.count),
                    "encoding": "utf8",
                    "atomic": "true"
                ]
            )
        } catch {
            return FileSystemOutput(
                success: false,
                content: "Error writing file: \(error.localizedDescription)",
                metadata: [
                    "operation": "write",
                    "error": error.localizedDescription,
                    "path": path
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
        // Resolve symbolic links for both paths to prevent escape via symlinks
        let pathURL = URL(fileURLWithPath: path)
        let workingDirURL = URL(fileURLWithPath: workingDirectory)
        
        let resolvedPath = pathURL.resolvingSymlinksInPath().standardized.path
        let resolvedWorkingDir = workingDirURL.resolvingSymlinksInPath().standardized.path
        
        // Ensure the resolved path starts with the resolved working directory
        return resolvedPath.hasPrefix(resolvedWorkingDir + "/") || resolvedPath == resolvedWorkingDir
    }
}

// MARK: - FileSystemActor

/// An actor to ensure thread-safe file system operations.
private actor FileSystemActor {
    private let maxFileSize = 1024 * 1024 // 1MB limit
    
    func fileExists(atPath path: String) -> Bool {
        FileManager.default.fileExists(atPath: path)
    }
    
    func fileExists(atPath path: String, isDirectory: inout ObjCBool) -> Bool {
        return FileManager.default.fileExists(atPath: path, isDirectory: &isDirectory)
    }
    
    func createDirectory(atPath path: String) throws {
        try FileManager.default.createDirectory(atPath: path, withIntermediateDirectories: true, attributes: nil)
    }
    
    func listDirectory(atPath path: String) throws -> [String] {
        return try FileManager.default.contentsOfDirectory(atPath: path)
    }
    
    func getFileInfo(atPath path: String) -> String {
        let fileManager = FileManager.default
        
        do {
            let attributes = try fileManager.attributesOfItem(atPath: path)
            let fileName = URL(fileURLWithPath: path).lastPathComponent
            
            let fileType = attributes[.type] as? FileAttributeType
            let fileSize = attributes[.size] as? Int64 ?? 0
            let modificationDate = attributes[.modificationDate] as? Date
            
            let typeString: String
            switch fileType {
            case .typeDirectory:
                typeString = "d"
            case .typeRegular:
                typeString = "-"
            case .typeSymbolicLink:
                typeString = "l"
            default:
                typeString = "?"
            }
            
            let sizeString = fileType == .typeDirectory ? "-" : String(fileSize)
            let dateString = modificationDate?.formatted(.dateTime.year().month().day().hour().minute()) ?? "Unknown"
            
            return "\(typeString) \(sizeString.padding(toLength: 10, withPad: " ", startingAt: 0)) \(dateString) \(fileName)"
        } catch {
            return "? Error \(URL(fileURLWithPath: path).lastPathComponent)"
        }
    }
}

// Make FileSystemOutput conform to PromptRepresentable for compatibility
extension FileSystemOutput: PromptRepresentable {
    public var promptRepresentation: Prompt {
        return Prompt(segments: [Prompt.Segment(text: description)])
    }
}