//
//  ReadTool.swift
//  SwiftAgent
//
//  Created by SwiftAgent on 2025/01/09.
//

import Foundation
import OpenFoundationModels
import SwiftAgent

/// A tool for reading file contents with line numbers.
///
/// `ReadTool` provides controlled file reading with line number formatting,
/// range selection, and safety checks.
///
/// ## Features
/// - Read entire files or specific line ranges
/// - Line number formatting (e.g., `123→content`)
/// - UTF-8 text file support
/// - Binary file detection and rejection
///
/// ## Limitations
/// - Maximum file size: 1MB
/// - UTF-8 encoding only
/// - Text files only (no binary support)
public struct ReadTool: OpenFoundationModels.Tool {
    public typealias Arguments = ReadInput
    public typealias Output = ReadOutput
    
    public static let name = "file_read"
    public var name: String { Self.name }
    
    public static let description = """
    Reads file contents with line numbers.
    
    Use this tool to:
    - Read entire text files
    - Read specific line ranges
    - View file contents with line numbers
    
    Features:
    - Line number formatting (123→content)
    - Range selection (startLine, endLine)
    - UTF-8 text file support
    
    Limitations:
    - Maximum file size: 1MB
    - Text files only (no binary)
    """
    
    public var description: String { Self.description }
    
    public var parameters: GenerationSchema {
        ReadInput.generationSchema
    }
    
    private let workingDirectory: String
    private let fsActor: FileSystemActor
    
    public init(workingDirectory: String = FileManager.default.currentDirectoryPath) {
        self.workingDirectory = workingDirectory
        self.fsActor = FileSystemActor(workingDirectory: workingDirectory)
    }
    
    public func call(arguments: ReadInput) async throws -> ReadOutput {
        // Normalize and validate path
        let normalizedPath = await fsActor.normalizePath(arguments.path)
        guard await fsActor.isPathSafe(normalizedPath) else {
            throw FileSystemError.pathNotSafe(path: arguments.path)
        }
        
        // Check if file exists
        guard await fsActor.fileExists(atPath: normalizedPath) else {
            throw FileSystemError.fileNotFound(path: normalizedPath)
        }
        
        // Check if it's a file (not a directory)
        var isDirectory: ObjCBool = false
        _ = await fsActor.fileExists(atPath: normalizedPath, isDirectory: &isDirectory)
        guard !isDirectory.boolValue else {
            throw FileSystemError.notAFile(path: normalizedPath)
        }
        
        // Read file content
        let content = try await fsActor.readFile(atPath: normalizedPath)
        
        // Split into lines
        let lines = content.components(separatedBy: .newlines)
        let totalLines = lines.count
        
        // Determine range to read
        let startLine = max(1, arguments.startLine)
        let endLine = arguments.endLine > 0 ? min(arguments.endLine, totalLines) : totalLines
        
        // Validate range
        guard startLine <= endLine else {
            throw FileSystemError.operationFailed(
                reason: "Invalid line range: start(\(startLine)) > end(\(endLine))"
            )
        }
        
        // Format output with line numbers
        var formattedLines: [String] = []
        for lineNum in startLine...min(endLine, totalLines) {
            let lineIndex = lineNum - 1
            if lineIndex < lines.count {
                let line = lines[lineIndex]
                // Use the same arrow format as Claude Code
                formattedLines.append("\(lineNum)→\(line)")
            }
        }
        
        let formattedContent = formattedLines.joined(separator: "\n")
        let linesRead = min(endLine, totalLines) - startLine + 1
        
        return ReadOutput(
            content: formattedContent,
            totalLines: totalLines,
            linesRead: linesRead,
            path: normalizedPath,
            startLine: startLine,
            endLine: min(endLine, totalLines)
        )
    }
}

// MARK: - Input/Output Types

/// Input structure for the read operation.
@Generable
public struct ReadInput: Sendable {
    /// The file path to read.
    public let path: String
    
    /// Starting line number (1-based, 0 for beginning).
    public let startLine: Int
    
    /// Ending line number (0 for end of file).
    public let endLine: Int
}

/// Output structure for the read operation.
public struct ReadOutput: Sendable {
    /// The formatted file content with line numbers.
    public let content: String
    
    /// Total number of lines in the file.
    public let totalLines: Int
    
    /// Number of lines actually read.
    public let linesRead: Int
    
    /// The normalized file path.
    public let path: String
    
    /// The actual start line read.
    public let startLine: Int
    
    /// The actual end line read.
    public let endLine: Int
    
    public init(
        content: String,
        totalLines: Int,
        linesRead: Int,
        path: String,
        startLine: Int,
        endLine: Int
    ) {
        self.content = content
        self.totalLines = totalLines
        self.linesRead = linesRead
        self.path = path
        self.startLine = startLine
        self.endLine = endLine
    }
}

extension ReadOutput: PromptRepresentable {
    public var promptRepresentation: Prompt {
        Prompt(description)
    }
}

extension ReadOutput: CustomStringConvertible {
    public var description: String {
        """
        Read Operation [Success]
        Path: \(path)
        Lines: \(startLine)-\(endLine) of \(totalLines) (\(linesRead) lines read)
        
        \(content)
        """
    }
}

