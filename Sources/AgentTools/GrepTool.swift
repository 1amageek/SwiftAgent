//
//  GrepTool.swift
//  SwiftAgent
//
//  Created by SwiftAgent on 2025/01/09.
//

import Foundation
import SwiftAgent

/// A powerful search tool built on regex pattern matching.
///
/// `GrepTool` provides comprehensive text search capabilities across files,
/// with multiple output modes, context control, file type filtering,
/// multiline matching, and result pagination.
public struct GrepTool: Tool {
    public typealias Arguments = GrepInput
    public typealias Output = GrepOutput

    public static let name = "Grep"
    public var name: String { Self.name }

    public static let description = """
    A powerful search tool for finding patterns in file contents.

    Usage:
    - ALWAYS use Grep for content search tasks. NEVER invoke grep or rg as a Bash command
    - Supports full regex syntax (e.g., "log.*Error", "function\\s+\\w+")
    - Filter files with glob parameter (e.g., "*.swift", "**/*.tsx") or type parameter (e.g., "swift", "py", "js")
    - Output modes: "content" shows matching lines, "files_with_matches" shows only file paths (default), "count" shows match counts
    - Use Dispatch tool for open-ended searches requiring multiple rounds
    - Pattern syntax: literal braces need escaping (use `interface\\{\\}` to find `interface{}`)
    - Multiline matching: By default patterns match within single lines only. For cross-line patterns like `struct \\{[\\s\\S]*?field`, use multiline: true

    Context control (requires output_mode "content"):
    - before_context (-B): lines to show before each match
    - after_context (-A): lines to show after each match
    - context (-C): lines to show before and after each match

    Pagination:
    - head_limit: Limit output to first N entries (0 = unlimited)
    - offset: Skip first N entries before applying head_limit
    """

    public var description: String { Self.description }

    public var parameters: GenerationSchema {
        GrepInput.generationSchema
    }

    private let workingDirectory: String
    private let fsActor: FileSystemActor

    /// Known file type extensions mapping (similar to ripgrep --type).
    private static let fileTypeExtensions: [String: [String]] = [
        "swift": ["swift"],
        "js": ["js", "mjs", "cjs"],
        "ts": ["ts", "mts", "cts"],
        "tsx": ["tsx"],
        "jsx": ["jsx"],
        "py": ["py", "pyi"],
        "rust": ["rs"],
        "go": ["go"],
        "java": ["java"],
        "kotlin": ["kt", "kts"],
        "c": ["c", "h"],
        "cpp": ["cpp", "cc", "cxx", "hpp", "hh", "hxx", "h"],
        "cs": ["cs"],
        "rb": ["rb"],
        "php": ["php"],
        "html": ["html", "htm"],
        "css": ["css"],
        "scss": ["scss"],
        "json": ["json"],
        "yaml": ["yaml", "yml"],
        "toml": ["toml"],
        "xml": ["xml"],
        "md": ["md", "markdown"],
        "sh": ["sh", "bash", "zsh"],
        "sql": ["sql"],
        "r": ["r", "R"],
        "lua": ["lua"],
        "dart": ["dart"],
        "zig": ["zig"],
    ]

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

        // Parse output mode
        let outputMode: OutputMode
        switch arguments.output_mode.lowercased() {
        case "content":
            outputMode = .content
        case "count":
            outputMode = .count
        case "files_with_matches", "":
            outputMode = .filesWithMatches
        default:
            outputMode = .filesWithMatches
        }

        // Resolve context lines: -A/-B take precedence, then -C, then context
        let resolvedContext = max(0, arguments.context)
        let contextBefore = arguments.before_context > 0 ? arguments.before_context : resolvedContext
        let contextAfter = arguments.after_context > 0 ? arguments.after_context : resolvedContext

        let showLineNumbers = arguments.show_line_numbers

        // Create regex pattern
        var regexOptions: NSRegularExpression.Options = []
        if arguments.ignore_case {
            regexOptions.insert(.caseInsensitive)
        }
        if arguments.multiline {
            regexOptions.insert(.dotMatchesLineSeparators)
        }

        let regex = try NSRegularExpression(pattern: arguments.pattern, options: regexOptions)

        // Build file glob pattern from type or glob parameter
        let filePattern = resolveFilePattern(glob: arguments.glob, type: arguments.type)

        // Find files to search
        let filesToSearch = try await findFilesToSearch(
            filePattern: filePattern,
            basePath: normalizedBasePath
        )

        // Search each file
        var allMatches: [GrepMatch] = []
        var filesSearched = 0
        var filesWithMatches: [String] = []
        var matchCountsByFile: [String: Int] = [:]

        // Pagination
        let headLimit = max(0, arguments.head_limit)
        let offset = max(0, arguments.offset)

        for filePath in filesToSearch {
            guard let fileContent = try? await fsActor.readFile(atPath: filePath) else {
                continue
            }

            filesSearched += 1

            let matches: [GrepMatch]
            if arguments.multiline {
                matches = searchFileMultiline(
                    content: fileContent,
                    regex: regex,
                    filePath: filePath,
                    contextBefore: contextBefore,
                    contextAfter: contextAfter,
                    showLineNumbers: showLineNumbers
                )
            } else {
                matches = searchFile(
                    content: fileContent,
                    regex: regex,
                    filePath: filePath,
                    contextBefore: contextBefore,
                    contextAfter: contextAfter,
                    showLineNumbers: showLineNumbers
                )
            }

            if !matches.isEmpty {
                filesWithMatches.append(filePath)
                matchCountsByFile[filePath] = matches.count
                allMatches.append(contentsOf: matches)
            }
        }

        // Apply pagination based on output mode
        let paginatedMatches: [GrepMatch]
        let paginatedFiles: [String]
        let paginatedCounts: [String: Int]

        switch outputMode {
        case .content:
            paginatedMatches = applyPagination(allMatches, offset: offset, limit: headLimit)
            paginatedFiles = filesWithMatches
            paginatedCounts = matchCountsByFile

        case .filesWithMatches:
            paginatedMatches = []
            paginatedFiles = applyPagination(filesWithMatches, offset: offset, limit: headLimit)
            paginatedCounts = [:]

        case .count:
            paginatedMatches = []
            paginatedFiles = []
            let sortedCounts = matchCountsByFile.sorted { $0.key < $1.key }
            let paginatedEntries = applyPagination(sortedCounts, offset: offset, limit: headLimit)
            paginatedCounts = Dictionary(uniqueKeysWithValues: paginatedEntries)
        }

        return GrepOutput(
            matches: paginatedMatches,
            filesSearched: filesSearched,
            totalMatches: allMatches.count,
            pattern: arguments.pattern,
            basePath: normalizedBasePath,
            outputMode: outputMode.rawValue,
            filesWithMatches: paginatedFiles,
            matchCounts: paginatedCounts
        )
    }

    // MARK: - Output Modes

    /// Supported output modes
    public enum OutputMode: String {
        case content = "content"
        case filesWithMatches = "files_with_matches"
        case count = "count"
    }

    // MARK: - Private Helpers

    private func resolveFilePattern(glob: String, type: String) -> String {
        // Type takes precedence if both are specified
        if !type.isEmpty {
            if let extensions = Self.fileTypeExtensions[type.lowercased()] {
                if extensions.count == 1 {
                    return "**/*.\(extensions[0])"
                }
                // Multiple extensions: use brace expansion equivalent
                // Since our glob doesn't support {}, enumerate each extension
                return extensions.map { "**/*.\($0)" }.joined(separator: "|")
            }
            // Unknown type, treat as extension
            return "**/*.\(type)"
        }

        if !glob.isEmpty {
            return glob
        }

        return "**/*"
    }

    private func findFilesToSearch(filePattern: String, basePath: String) async throws -> [String] {
        var isDirectory: ObjCBool = false
        guard await fsActor.fileExists(atPath: basePath, isDirectory: &isDirectory) else {
            throw FileSystemError.fileNotFound(path: basePath)
        }

        if !isDirectory.boolValue {
            return [basePath]
        }

        // Handle multi-pattern (from type with multiple extensions)
        let patterns = filePattern.components(separatedBy: "|")

        var allFiles: Set<String> = []
        let globTool = GlobTool(workingDirectory: workingDirectory)

        for pattern in patterns {
            let globInputContent = GeneratedContent(properties: [
                "pattern": pattern.trimmingCharacters(in: .whitespaces),
                "path": basePath,
                "file_type": "file"
            ])
            let globInput = try GlobInput(globInputContent)
            let globOutput = try await globTool.call(arguments: globInput)
            allFiles.formUnion(globOutput.files)
        }

        return allFiles.sorted()
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
        // Track which lines are already shown as context to avoid duplicates
        var lastContextEnd = -1

        for (index, line) in lines.enumerated() {
            let lineNumber = index + 1
            let range = NSRange(location: 0, length: line.utf16.count)

            if regex.firstMatch(in: line, options: [], range: range) != nil {
                var contextLines: [String] = []

                // Add before context (avoid overlapping with previous match context)
                if contextBefore > 0 {
                    let startLine = max(0, index - contextBefore)
                    let effectiveStart = max(startLine, lastContextEnd + 1)
                    if effectiveStart < index && effectiveStart > startLine {
                        contextLines.append("---")
                    }
                    for i in effectiveStart..<index {
                        let prefix = showLineNumbers ? "\(i + 1): " : ""
                        contextLines.append("\(prefix)\(lines[i])")
                    }
                }

                // Add matching line
                let matchPrefix = showLineNumbers ? "\(lineNumber)→ " : ""
                contextLines.append("\(matchPrefix)\(line)")

                // Add after context
                if contextAfter > 0 {
                    let endLine = min(lines.count, index + 1 + contextAfter)
                    for i in (index + 1)..<endLine {
                        let prefix = showLineNumbers ? "\(i + 1): " : ""
                        contextLines.append("\(prefix)\(lines[i])")
                    }
                    lastContextEnd = endLine - 1
                } else {
                    lastContextEnd = index
                }

                matches.append(GrepMatch(
                    file: filePath,
                    line: lineNumber,
                    content: line,
                    context: contextLines.joined(separator: "\n")
                ))
            }
        }

        return matches
    }

    private func searchFileMultiline(
        content: String,
        regex: NSRegularExpression,
        filePath: String,
        contextBefore: Int,
        contextAfter: Int,
        showLineNumbers: Bool
    ) -> [GrepMatch] {
        var matches: [GrepMatch] = []
        let range = NSRange(location: 0, length: content.utf16.count)
        let lines = content.components(separatedBy: .newlines)

        regex.enumerateMatches(in: content, options: [], range: range) { result, _, _ in
            guard let result = result,
                  let matchRange = Range(result.range, in: content) else { return }

            let matchedText = String(content[matchRange])

            // Calculate line number of match start
            let beforeMatch = String(content[content.startIndex..<matchRange.lowerBound])
            let matchStartLine = beforeMatch.components(separatedBy: .newlines).count
            let matchEndLine = matchStartLine + matchedText.components(separatedBy: .newlines).count - 1

            // Build context
            var contextLines: [String] = []

            // Before context
            if contextBefore > 0 {
                let startIdx = max(0, matchStartLine - 1 - contextBefore)
                for i in startIdx..<(matchStartLine - 1) {
                    if i < lines.count {
                        let prefix = showLineNumbers ? "\(i + 1): " : ""
                        contextLines.append("\(prefix)\(lines[i])")
                    }
                }
            }

            // Matched lines
            for i in (matchStartLine - 1)..<min(matchEndLine, lines.count) {
                let prefix = showLineNumbers ? "\(i + 1)→ " : ""
                contextLines.append("\(prefix)\(lines[i])")
            }

            // After context
            if contextAfter > 0 {
                let endIdx = min(lines.count, matchEndLine + contextAfter)
                for i in matchEndLine..<endIdx {
                    if i < lines.count {
                        let prefix = showLineNumbers ? "\(i + 1): " : ""
                        contextLines.append("\(prefix)\(lines[i])")
                    }
                }
            }

            matches.append(GrepMatch(
                file: filePath,
                line: matchStartLine,
                content: matchedText,
                context: contextLines.joined(separator: "\n")
            ))
        }

        return matches
    }

    private func applyPagination<T>(_ items: [T], offset: Int, limit: Int) -> [T] {
        guard offset > 0 || limit > 0 else { return items }

        let startIndex = min(offset, items.count)
        let sliced = Array(items.dropFirst(startIndex))

        if limit > 0 {
            return Array(sliced.prefix(limit))
        }
        return sliced
    }
}

// MARK: - Input/Output Types

/// Input structure for the grep operation.
@Generable
public struct GrepInput: Sendable {
    @Guide(description: "The regular expression pattern to search for in file contents")
    public let pattern: String

    @Guide(description: "File or directory to search in. Defaults to current working directory.")
    public let path: String

    @Guide(description: "Glob pattern to filter files (e.g. \"*.swift\", \"*.{ts,tsx}\")")
    public let glob: String

    @Guide(description: "Output mode: \"content\" shows matching lines, \"files_with_matches\" shows file paths (default), \"count\" shows match counts")
    public let output_mode: String

    @Guide(description: "Number of lines to show before each match. Requires output_mode \"content\".")
    public let before_context: Int

    @Guide(description: "Number of lines to show after each match. Requires output_mode \"content\".")
    public let after_context: Int

    @Guide(description: "Number of lines to show before and after each match. Requires output_mode \"content\".")
    public let context: Int

    @Guide(description: "Show line numbers in output. Defaults to true.")
    public let show_line_numbers: Bool

    @Guide(description: "Case insensitive search")
    public let ignore_case: Bool

    @Guide(description: "File type to search (e.g., \"swift\", \"py\", \"js\"). More efficient than glob for standard file types.")
    public let type: String

    @Guide(description: "Limit output to first N entries. 0 means unlimited.")
    public let head_limit: Int

    @Guide(description: "Skip first N entries before applying head_limit.")
    public let offset: Int

    @Guide(description: "Enable multiline mode where . matches newlines and patterns can span lines. Default: false.")
    public let multiline: Bool
}

/// A single grep match result.
public struct GrepMatch: Sendable {
    /// The file containing the match.
    public let file: String

    /// The line number of the match (1-based).
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
