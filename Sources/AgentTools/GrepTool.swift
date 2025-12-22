//
//  GrepTool.swift
//  SwiftAgent
//
//  Created by SwiftAgent on 2025/01/09.
//

import Foundation
import OpenFoundationModels
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
public struct GrepTool: OpenFoundationModels.Tool {
    public typealias Arguments = GrepInput
    public typealias Output = GrepOutput

    public static let name = "text_search"
    public var name: String { Self.name }

    /// Supported output modes
    public enum OutputMode: String {
        case content = "content"
        case filesWithMatches = "files_with_matches"
        case count = "count"
    }

    public static let description = """
    A powerful search tool built on regex pattern matching.

    Usage:
    - Supports full regex syntax (e.g., "log.*Error", "function\\s+\\w+")
    - Filter files with glob parameter (e.g., "*.swift", "**/*.tsx")
    - Output modes: "content" shows matching lines, "files_with_matches" shows only file paths (default), "count" shows match counts
    - Use headLimit to limit results

    Options:
    - ignoreCase: Case insensitive search (like -i)
    - contextBefore/After: Lines to show around matches (like -B/-A/-C)
    - multiline: Enable cross-line pattern matching
    - headLimit: Limit output entries

    Examples:
    - Pattern: "TODO:" finds all TODO comments
    - Pattern: "func\\s+\\w+" finds function definitions
    - Pattern: "error|warning" finds errors or warnings (case insensitive with ignoreCase=true)
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
        let normalizedBasePath = await fsActor.normalizePath(arguments.basePath)
        guard await fsActor.isPathSafe(normalizedBasePath) else {
            throw FileSystemError.pathNotSafe(path: arguments.basePath)
        }

        // Parse output mode
        let outputMode: OutputMode
        switch arguments.outputMode.lowercased() {
        case "content":
            outputMode = .content
        case "count":
            outputMode = .count
        case "files_with_matches", "":
            outputMode = .filesWithMatches
        default:
            throw FileSystemError.operationFailed(
                reason: "outputMode must be 'content', 'files_with_matches', or 'count', got: '\(arguments.outputMode)'"
            )
        }

        let contextBefore = max(0, arguments.contextBefore)
        let contextAfter = max(0, arguments.contextAfter)

        // Create regex pattern
        var regexOptions: NSRegularExpression.Options = []
        if arguments.ignoreCase {
            regexOptions.insert(.caseInsensitive)
        }
        if arguments.multiline {
            regexOptions.insert(.dotMatchesLineSeparators)
        }

        let regex = try NSRegularExpression(pattern: arguments.pattern, options: regexOptions)

        // Find files to search using glob pattern
        let filesToSearch = try await findFilesToSearch(
            filePattern: arguments.glob,
            basePath: normalizedBasePath
        )

        // Search each file
        var allMatches: [GrepMatch] = []
        var filesSearched = 0
        var filesWithMatches: [String] = []
        var matchCountsByFile: [String: Int] = [:]
        let headLimit = arguments.headLimit > 0 ? arguments.headLimit : Int.max
        let offset = max(0, arguments.offset)

        for filePath in filesToSearch {
            // Skip if not a text file
            guard let fileContent = try? await fsActor.readFile(atPath: filePath) else {
                continue  // Skip binary or unreadable files
            }

            filesSearched += 1

            // Search file content
            let matches: [GrepMatch]
            if arguments.multiline {
                matches = searchFileMultiline(
                    content: fileContent,
                    regex: regex,
                    filePath: filePath,
                    contextBefore: contextBefore,
                    contextAfter: contextAfter
                )
            } else {
                matches = searchFile(
                    content: fileContent,
                    regex: regex,
                    filePath: filePath,
                    contextBefore: contextBefore,
                    contextAfter: contextAfter,
                    showLineNumbers: arguments.showLineNumbers
                )
            }

            if !matches.isEmpty {
                filesWithMatches.append(filePath)
                matchCountsByFile[filePath] = matches.count
                allMatches.append(contentsOf: matches)
            }
        }

        // Apply offset and head_limit based on output mode
        let finalMatches: [GrepMatch]
        let finalFilesWithMatches: [String]
        let finalMatchCounts: [String: Int]

        switch outputMode {
        case .content:
            let sliced = Array(allMatches.dropFirst(offset).prefix(headLimit))
            finalMatches = sliced
            finalFilesWithMatches = filesWithMatches
            finalMatchCounts = matchCountsByFile
        case .filesWithMatches:
            let sliced = Array(filesWithMatches.dropFirst(offset).prefix(headLimit))
            finalFilesWithMatches = sliced
            finalMatches = []
            finalMatchCounts = [:]
        case .count:
            let sliced = Array(matchCountsByFile.keys.sorted().dropFirst(offset).prefix(headLimit))
            finalMatchCounts = Dictionary(uniqueKeysWithValues: sliced.map { ($0, matchCountsByFile[$0]!) })
            finalFilesWithMatches = []
            finalMatches = []
        }

        return GrepOutput(
            matches: finalMatches,
            filesSearched: filesSearched,
            totalMatches: allMatches.count,
            pattern: arguments.pattern,
            basePath: normalizedBasePath,
            outputMode: outputMode.rawValue,
            filesWithMatches: finalFilesWithMatches,
            matchCounts: finalMatchCounts
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
            "basePath": basePath,
            "fileType": "file"
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
    @Guide(description: "The regular expression pattern to search for in file contents")
    public let pattern: String

    @Guide(description: "Glob pattern to filter files (e.g., \"*.swift\", \"**/*.tsx\"). Defaults to all files if empty.")
    public let glob: String

    @Guide(description: "File or directory path to search in. Defaults to current working directory.")
    public let basePath: String

    @Guide(description: "Case insensitive search (like rg -i)")
    public let ignoreCase: Bool

    @Guide(description: "Number of lines to show before each match (like rg -B)")
    public let contextBefore: Int

    @Guide(description: "Number of lines to show after each match (like rg -A)")
    public let contextAfter: Int

    @Guide(description: "Output mode: 'content' shows matching lines, 'files_with_matches' shows only file paths (default), 'count' shows match counts")
    public let outputMode: String

    @Guide(description: "Limit output to first N entries. 0 means unlimited.")
    public let headLimit: Int

    @Guide(description: "Skip first N entries before applying headLimit. Defaults to 0.")
    public let offset: Int

    @Guide(description: "Enable multiline mode where . matches newlines and patterns can span lines")
    public let multiline: Bool

    @Guide(description: "Show line numbers in output. Defaults to true.")
    public let showLineNumbers: Bool
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

