//
//  ReadTool.swift
//  SwiftAgent
//
//  Created by SwiftAgent on 2025/01/09.
//

import Foundation
import SwiftAgent

/// A tool for reading file contents from the local filesystem.
///
/// `ReadTool` provides controlled file reading with line number formatting,
/// offset/limit pagination, and safety checks.
///
/// ## Features
/// - Read entire files or specific line ranges with offset/limit
/// - Line number formatting (e.g., `123→content`)
/// - UTF-8 text file support
/// - Default limit of 2000 lines (configurable)
/// - Long line truncation (2000 characters)
///
/// ## Path Formats
/// - Absolute paths: `/path/to/file`
/// - Home directory: `~/path/to/file`
/// - Relative paths: `path/to/file`
///
/// ## Limitations
/// - Maximum file size: 1MB
/// - UTF-8 encoding only
/// - Text files only (no binary support)
public struct ReadTool: Tool {
    public typealias Arguments = ReadInput
    public typealias Output = ReadOutput

    public static let name = "Read"
    public var name: String { Self.name }

    /// Default number of lines to read if no limit specified
    public static let defaultLineLimit = 2000

    /// Maximum characters per line before truncation
    public static let maxLineLength = 2000

    public static let description = """
    Reads a file from the local filesystem. You can access any file directly by using this tool.
    Assume this tool is able to read all files on the machine. If the user provides a path to a file assume that path is valid. It is okay to read a file that does not exist; an error will be returned.

    Usage:
    - The file_path parameter supports absolute paths, relative paths, or ~/ paths
    - By default, it reads up to 2000 lines starting from the beginning of the file
    - You can optionally specify a line offset and limit (especially handy for long files), but it's recommended to read the whole file by not providing these parameters
    - Any lines longer than 2000 characters will be truncated
    - Results are returned with line numbers starting at 1 (e.g., "1→content")
    - This tool can only read files, not directories. To read a directory, use an ls command via the Bash tool
    - You can call multiple tools in a single response. It is always better to speculatively read multiple potentially useful files in parallel
    - If you read a file that exists but has empty contents you will receive an empty string
    - NEVER use the Bash tool with cat, head, or tail to read files. ALWAYS use this tool instead
    - Maximum file size: 1MB, UTF-8 text files only
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
        let normalizedPath = await fsActor.normalizePath(arguments.file_path)
        guard await fsActor.isPathSafe(normalizedPath) else {
            throw FileSystemError.pathNotSafe(path: arguments.file_path)
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

        // Calculate offset and limit
        // offset is 0-based line index, limit is number of lines to read
        let offset = max(0, arguments.offset)
        let limit = arguments.limit > 0 ? arguments.limit : Self.defaultLineLimit

        // Convert to 1-based line numbers for output
        let startLine = offset + 1
        let endLine = min(offset + limit, totalLines)

        // Validate range
        guard startLine <= totalLines else {
            return ReadOutput(
                content: "",
                totalLines: totalLines,
                linesRead: 0,
                path: normalizedPath,
                startLine: startLine,
                endLine: startLine,
                truncatedLines: 0
            )
        }

        // Format output with line numbers
        var formattedLines: [String] = []
        var truncatedLines = 0

        for lineNum in startLine...endLine {
            let lineIndex = lineNum - 1
            if lineIndex < lines.count {
                var line = lines[lineIndex]

                // Truncate long lines
                if line.count > Self.maxLineLength {
                    line = String(line.prefix(Self.maxLineLength)) + "..."
                    truncatedLines += 1
                }

                // Format: lineNumber→content
                formattedLines.append("\(lineNum)→\(line)")
            }
        }

        let formattedContent = formattedLines.joined(separator: "\n")
        let linesRead = formattedLines.count

        return ReadOutput(
            content: formattedContent,
            totalLines: totalLines,
            linesRead: linesRead,
            path: normalizedPath,
            startLine: startLine,
            endLine: endLine,
            truncatedLines: truncatedLines
        )
    }
}

// MARK: - Input/Output Types

/// Input structure for the read operation.
@Generable
public struct ReadInput: Sendable {
    @Guide(description: "File path (absolute, relative, or ~/)")
    public let file_path: String

    @Guide(description: "Line offset to start from (0-based, default: 0)")
    public let offset: Int

    @Guide(description: "Number of lines to read (default: 2000)")
    public let limit: Int
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

    /// The actual start line read (1-based).
    public let startLine: Int

    /// The actual end line read (1-based).
    public let endLine: Int

    /// Number of lines that were truncated due to length.
    public let truncatedLines: Int

    public init(
        content: String,
        totalLines: Int,
        linesRead: Int,
        path: String,
        startLine: Int,
        endLine: Int,
        truncatedLines: Int = 0
    ) {
        self.content = content
        self.totalLines = totalLines
        self.linesRead = linesRead
        self.path = path
        self.startLine = startLine
        self.endLine = endLine
        self.truncatedLines = truncatedLines
    }
}

extension ReadOutput: PromptRepresentable {
    public var promptRepresentation: Prompt {
        Prompt(description)
    }
}

extension ReadOutput: CustomStringConvertible {
    public var description: String {
        let truncateNote = truncatedLines > 0 ? " (\(truncatedLines) lines truncated)" : ""
        return """
        Read Operation [Success]
        Path: \(path)
        Lines: \(startLine)-\(endLine) of \(totalLines) (\(linesRead) lines read)\(truncateNote)

        \(content)
        """
    }
}

