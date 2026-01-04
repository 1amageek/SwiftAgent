//
//  GrepTool.swift
//  SwiftAgent
//
//  Created by SwiftAgent on 2025/01/09.
//

import Foundation
import SwiftAgent

/// A powerful search tool for finding patterns in file contents.
///
/// `GrepTool` provides powerful text search capabilities across multiple files,
/// with regex pattern matching, context display, and multiple output modes.
///
/// ## Features
/// - Full regex syntax (similar to ripgrep)
/// - Case-insensitive search (-i)
/// - Context lines before/after matches (-A/-B/-C)
/// - Multiple output modes: content, files_with_matches, count
/// - File type filtering
/// - Result limiting with head_limit
/// - Multiline matching support
///
/// ## Pattern Syntax
/// - Uses regex patterns (not glob patterns)
/// - Literal braces need escaping: `interface\{\}` to find `interface{}`
/// - Common patterns: `log.*Error`, `function\s+\w+`
///
/// ## Limitations
/// - Text files only (skips binary files)
/// - Maximum file size: 1MB per file
/// - UTF-8 encoding only
public struct GrepTool: Tool {
    public typealias Arguments = GrepInput
    public typealias Output = GrepOutput

    public static let name = "Grep"
    public var name: String { Self.name }

    /// Supported output modes
    public enum OutputMode: String {
        case content = "content"
        case filesWithMatches = "files_with_matches"
        case count = "count"
    }

    public static let description = """
    Search for regex pattern in files. Returns matching lines with file paths and line numbers. \
    Use include to filter by file pattern (e.g., "*.swift").
    """

    public var description: String { Self.description }

    public var parameters: GenerationSchema {
        GrepInput.generationSchema
    }

    private let workingDirectory: String
    private let fsActor: FileSystemActor

    public init(workingDirectory: String = FileManager.default.currentDirectoryPath) {
        self.workingDirectory = workingDirectory
        self.fsActor = FileSystemActor(workingDirectory: workingDirectory)
    }

    public func call(arguments: GrepInput) async throws -> GrepOutput {
        // Normalize and validate base path
        let basePath = arguments.path.isEmpty ? workingDirectory : arguments.path
        let normalizedBasePath = await fsActor.normalizePath(basePath)
        guard await fsActor.isPathSafe(normalizedBasePath) else {
            throw FileSystemError.pathNotSafe(path: basePath)
        }

        // Default to content output mode for simplified API
        let outputMode: OutputMode = .content

        let contextLines = max(0, arguments.context)

        // Create regex pattern
        var regexOptions: NSRegularExpression.Options = []
        if arguments.ignore_case {
            regexOptions.insert(.caseInsensitive)
        }

        let regex = try NSRegularExpression(pattern: arguments.pattern, options: regexOptions)

        // Find files to search using include pattern
        let filesToSearch = try await findFilesToSearch(
            filePattern: arguments.include,
            basePath: normalizedBasePath
        )

        // Search each file
        var allMatches: [GrepMatch] = []
        var filesSearched = 0
        var filesWithMatches: [String] = []
        var matchCountsByFile: [String: Int] = [:]

        for filePath in filesToSearch {
            // Skip if not a text file
            guard let fileContent = try? await fsActor.readFile(atPath: filePath) else {
                continue  // Skip binary or unreadable files
            }

            filesSearched += 1

            // Search file content
            let matches = searchFile(
                content: fileContent,
                regex: regex,
                filePath: filePath,
                contextBefore: contextLines,
                contextAfter: contextLines,
                showLineNumbers: true
            )

            if !matches.isEmpty {
                filesWithMatches.append(filePath)
                matchCountsByFile[filePath] = matches.count
                allMatches.append(contentsOf: matches)
            }
        }

        // Return all matches in content mode
        return GrepOutput(
            matches: allMatches,
            filesSearched: filesSearched,
            totalMatches: allMatches.count,
            pattern: arguments.pattern,
            basePath: normalizedBasePath,
            outputMode: outputMode.rawValue,
            filesWithMatches: filesWithMatches,
            matchCounts: matchCountsByFile
        )
    }

    private func findFilesToSearch(filePattern: String, basePath: String) async throws -> [String] {
        // Check if basePath is a file or directory
        var isDirectory: ObjCBool = false
        guard await fsActor.fileExists(atPath: basePath, isDirectory: &isDirectory) else {
            throw FileSystemError.fileNotFound(path: basePath)
        }

        if !isDirectory.boolValue {
            // Single file specified
            return [basePath]
        }

        // Determine pattern - default to all files if empty
        let pattern = filePattern.isEmpty ? "**/*" : filePattern

        // Use glob pattern to find files
        let globTool = GlobTool(workingDirectory: workingDirectory)

        // Create GeneratedContent for GlobInput
        let globInputContent = GeneratedContent(properties: [
            "pattern": pattern,
            "path": basePath,
            "file_type": "file"
        ])
        let globInput = try GlobInput(globInputContent)

        let globOutput = try await globTool.call(arguments: globInput)
        return globOutput.files
    }

    private func searchFile(
        content: String,
        regex: NSRegularExpression,
        filePath: String,
        contextBefore: Int,
        contextAfter: Int,
        showLineNumbers: Bool
    ) -> [GrepMatch] {
        let lines = content.components(separatedBy: .newlines)
        var matches: [GrepMatch] = []

        for (index, line) in lines.enumerated() {
            let lineNumber = index + 1
            let range = NSRange(location: 0, length: line.utf16.count)

            if regex.firstMatch(in: line, options: [], range: range) != nil {
                // Build context
                var contextLines: [String] = []

                // Add before context
                if contextBefore > 0 {
                    let startLine = max(0, index - contextBefore)
                    for i in startLine..<index {
                        let prefix = showLineNumbers ? "\(i + 1): " : ""
                        contextLines.append("\(prefix)\(lines[i])")
                    }
                }

                // Add matching line (highlighted)
                let matchPrefix = showLineNumbers ? "\(lineNumber)→ " : ""
                contextLines.append("\(matchPrefix)\(line)")

                // Add after context
                if contextAfter > 0 {
                    let endLine = min(lines.count, index + 1 + contextAfter)
                    for i in (index + 1)..<endLine {
                        let prefix = showLineNumbers ? "\(i + 1): " : ""
                        contextLines.append("\(prefix)\(lines[i])")
                    }
                }

                let match = GrepMatch(
                    file: filePath,
                    line: lineNumber,
                    content: line,
                    context: contextLines.joined(separator: "\n")
                )

                matches.append(match)
            }
        }

        return matches
    }

    private func searchFileMultiline(
        content: String,
        regex: NSRegularExpression,
        filePath: String,
        contextBefore: Int,
        contextAfter: Int
    ) -> [GrepMatch] {
        var matches: [GrepMatch] = []
        let range = NSRange(location: 0, length: content.utf16.count)

        regex.enumerateMatches(in: content, options: [], range: range) { result, _, _ in
            guard let result = result else { return }

            // Get the matched string
            if let matchRange = Range(result.range, in: content) {
                let matchedText = String(content[matchRange])

                // Calculate line number of match start
                let beforeMatch = String(content[content.startIndex..<matchRange.lowerBound])
                let lineNumber = beforeMatch.components(separatedBy: .newlines).count

                let match = GrepMatch(
                    file: filePath,
                    line: lineNumber,
                    content: matchedText,
                    context: matchedText
                )
                matches.append(match)
            }
        }

        return matches
    }
}

// MARK: - Input/Output Types

/// Input structure for the grep operation.
@Generable
public struct GrepInput: Sendable {
    @Guide(description: "Regex pattern to search")
    public let pattern: String

    @Guide(description: "File pattern filter (e.g., \"*.swift\")")
    public let include: String

    @Guide(description: "Directory to search (default: current dir)")
    public let path: String

    @Guide(description: "Case insensitive search")
    public let ignore_case: Bool

    @Guide(description: "Context lines around matches")
    public let context: Int
}

/// A single grep match result.
public struct GrepMatch: Sendable {
    /// The file containing the match.
    public let file: String

    /// The line number of the match.
    public let line: Int

    /// The matching line content.
    public let content: String

    /// The match with surrounding context.
    public let context: String

    public init(file: String, line: Int, content: String, context: String) {
        self.file = file
        self.line = line
        self.content = content
        self.context = context
    }
}

/// Output structure for the grep operation.
public struct GrepOutput: Sendable {
    /// List of all matches found (when outputMode is "content").
    public let matches: [GrepMatch]

    /// Number of files searched.
    public let filesSearched: Int

    /// Total number of matches found.
    public let totalMatches: Int

    /// The pattern that was searched.
    public let pattern: String

    /// The base path that was searched.
    public let basePath: String

    /// The output mode used.
    public let outputMode: String

    /// List of files with matches (when outputMode is "files_with_matches").
    public let filesWithMatches: [String]

    /// Match counts by file (when outputMode is "count").
    public let matchCounts: [String: Int]

    public init(
        matches: [GrepMatch],
        filesSearched: Int,
        totalMatches: Int,
        pattern: String,
        basePath: String,
        outputMode: String = "files_with_matches",
        filesWithMatches: [String] = [],
        matchCounts: [String: Int] = [:]
    ) {
        self.matches = matches
        self.filesSearched = filesSearched
        self.totalMatches = totalMatches
        self.pattern = pattern
        self.basePath = basePath
        self.outputMode = outputMode
        self.filesWithMatches = filesWithMatches
        self.matchCounts = matchCounts
    }
}

extension GrepOutput: PromptRepresentable {
    public var promptRepresentation: Prompt {
        Prompt(description)
    }
}

extension GrepOutput: CustomStringConvertible {
    public var description: String {
        let header = """
        Grep Search [Found \(totalMatches) match(es) in \(filesSearched) file(s)]
        Pattern: \(pattern)
        Base: \(basePath)
        Mode: \(outputMode)
        """

        switch outputMode {
        case "files_with_matches":
            if filesWithMatches.isEmpty {
                return header + "\n\nNo matches found"
            }
            return header + "\n\n" + filesWithMatches.joined(separator: "\n")

        case "count":
            if matchCounts.isEmpty {
                return header + "\n\nNo matches found"
            }
            let counts = matchCounts.sorted { $0.key < $1.key }
                .map { "\($0.key): \($0.value)" }
                .joined(separator: "\n")
            return header + "\n\n" + counts

        case "content":
            if matches.isEmpty {
                return header + "\n\nNo matches found"
            }

            var output = header + "\n"

            // Group matches by file
            let groupedMatches = Dictionary(grouping: matches, by: { $0.file })

            for (file, fileMatches) in groupedMatches.sorted(by: { $0.key < $1.key }) {
                output += "\n\n\(file):"
                for match in fileMatches {
                    output += "\n\(match.context)"
                }
            }

            return output

        default:
            return header
        }
    }
}

