//
//  WriteTool.swift
//  SwiftAgent
//
//  Created by SwiftAgent on 2025/01/09.
//

import Foundation
import OpenFoundationModels
import SwiftAgent

/// A tool for writing content to files.
///
/// `WriteTool` provides controlled file writing with automatic directory creation,
/// atomic writes, and safety checks.
///
/// ## Features
/// - Create new files or overwrite existing ones
/// - Automatic parent directory creation
/// - Atomic write operations (prevent partial writes)
/// - UTF-8 text file support
///
/// ## Limitations
/// - Maximum content size: 1MB
/// - UTF-8 encoding only
/// - Operates only within working directory
public struct WriteTool: OpenFoundationModels.Tool {
    public typealias Arguments = WriteInput
    public typealias Output = WriteOutput
    
    public static let name = "write"
    public var name: String { Self.name }
    
    public static let description = """
    Writes content to a file.
    
    Use this tool to:
    - Create new text files
    - Overwrite existing files
    - Save generated content
    
    Features:
    - Automatic parent directory creation
    - Atomic write operations
    - UTF-8 text encoding
    
    Limitations:
    - Maximum content size: 1MB
    - Text files only
    """
    
    public var description: String { Self.description }
    
    private let workingDirectory: String
    private let fsActor: FileSystemActor
    
    public init(workingDirectory: String = FileManager.default.currentDirectoryPath) {
        self.workingDirectory = workingDirectory
        self.fsActor = FileSystemActor(workingDirectory: workingDirectory)
    }
    
    public func call(arguments: WriteInput) async throws -> WriteOutput {
        // Normalize and validate path
        let normalizedPath = await fsActor.normalizePath(arguments.path)
        guard await fsActor.isPathSafe(normalizedPath) else {
            throw FileSystemError.pathNotSafe(path: arguments.path)
        }
        
        // Check if file exists (for informational purposes)
        let fileExists = await fsActor.fileExists(atPath: normalizedPath)
        var isDirectory: ObjCBool = false
        if fileExists {
            _ = await fsActor.fileExists(atPath: normalizedPath, isDirectory: &isDirectory)
            guard !isDirectory.boolValue else {
                throw FileSystemError.notAFile(path: normalizedPath)
            }
        }
        
        // Write the file
        try await fsActor.writeFile(content: arguments.content, toPath: normalizedPath)
        
        // Get the byte count
        let bytesWritten = arguments.content.data(using: .utf8)?.count ?? 0
        
        return WriteOutput(
            success: true,
            bytesWritten: bytesWritten,
            path: normalizedPath,
            overwrote: fileExists,
            message: fileExists ? "File overwritten successfully" : "File created successfully"
        )
    }
}

// MARK: - Input/Output Types

/// Input structure for the write operation.
@Generable
public struct WriteInput {
    /// The file path to write to.
    @Guide(description: "File path to write to")
    public let path: String
    
    /// The content to write to the file.
    @Guide(description: "Content to write to the file")
    public let content: String
}

/// Output structure for the write operation.
public struct WriteOutput: Codable, Sendable, CustomStringConvertible {
    /// Whether the operation was successful.
    public let success: Bool
    
    /// Number of bytes written.
    public let bytesWritten: Int
    
    /// The normalized file path.
    public let path: String
    
    /// Whether an existing file was overwritten.
    public let overwrote: Bool
    
    /// A descriptive message about the operation.
    public let message: String
    
    public init(
        success: Bool,
        bytesWritten: Int,
        path: String,
        overwrote: Bool,
        message: String
    ) {
        self.success = success
        self.bytesWritten = bytesWritten
        self.path = path
        self.overwrote = overwrote
        self.message = message
    }
    
    public var description: String {
        """
        Write Operation [\(success ? "Success" : "Failed")]
        Path: \(path)
        Bytes written: \(bytesWritten)
        \(message)
        """
    }
}

// Make WriteOutput conform to PromptRepresentable
extension WriteOutput: PromptRepresentable {
    public var promptRepresentation: Prompt {
        Prompt(description)
    }
}