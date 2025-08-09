//
//  GrepTool.swift
//  SwiftAgent
//
//  Created by SwiftAgent on 2025/01/09.
//

import Foundation
import OpenFoundationModels
import SwiftAgent

/// A tool for searching file contents using regular expressions.
///
/// `GrepTool` provides powerful text search capabilities across multiple files,
/// with regex pattern matching and context display.
///
/// ## Features
/// - Regular expression pattern matching
/// - Case-insensitive search option
/// - Context lines before/after matches
/// - Multi-file search with glob patterns
/// - Line number reporting
///
/// ## Limitations
/// - Text files only (skips binary files)
/// - Maximum file size: 1MB per file
/// - UTF-8 encoding only
public struct GrepTool: OpenFoundationModels.Tool {
    public typealias Arguments = GrepInput
    public typealias Output = GrepOutput
    
    public static let name = "grep"
    public var name: String { Self.name }
    
    public static let description = """
    Searches file contents using regular expressions.
    
    Use this tool to:
    - Find text patterns in files
    - Search for function/variable usage
    - Locate error messages or TODOs
    
    Features:
    - Regex pattern matching
    - Case-insensitive option
    - Context lines (before/after)
    - Multi-file search
    
    Examples:
    - Pattern: "TODO:" finds all TODO comments
    - Pattern: "func\\s+\\w+" finds function definitions
    - Pattern: "error|warning" finds errors or warnings
    """
    
    public var description: String { Self.description }
    
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
        
        // Parse options with strict validation
        let ignoreCase: Bool
        switch arguments.ignoreCase.lowercased() {
        case "true":
            ignoreCase = true
        case "false", "":
            ignoreCase = false
        default:
            throw FileSystemError.operationFailed(
                reason: "ignoreCase must be 'true' or 'false', got: '\(arguments.ignoreCase)'"
            )
        }
        let contextBefore = max(0, arguments.contextBefore)
        let contextAfter = max(0, arguments.contextAfter)
        
        // Create regex pattern
        let regexOptions: NSRegularExpression.Options = ignoreCase ? [.caseInsensitive] : []
        let regex = try NSRegularExpression(pattern: arguments.pattern, options: regexOptions)
        
        // Find files to search using glob pattern
        let filesToSearch = try await findFilesToSearch(
            filePattern: arguments.filePattern,
            basePath: normalizedBasePath
        )
        
        // Search each file
        var allMatches: [GrepMatch] = []
        var filesSearched = 0
        
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
                contextBefore: contextBefore,
                contextAfter: contextAfter
            )
            
            allMatches.append(contentsOf: matches)
        }
        
        return GrepOutput(
            matches: allMatches,
            filesSearched: filesSearched,
            totalMatches: allMatches.count,
            pattern: arguments.pattern,
            basePath: normalizedBasePath
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
        
        // Use glob pattern to find files
        let globTool = GlobTool(workingDirectory: workingDirectory)
        
        // Create GeneratedContent for GlobInput
        let globInputContent = GeneratedContent(properties: [
            "pattern": filePattern,
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
        contextAfter: Int
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
                        contextLines.append("\(i + 1): \(lines[i])")
                    }
                }
                
                // Add matching line (highlighted)
                contextLines.append("\(lineNumber)→ \(line)")
                
                // Add after context
                if contextAfter > 0 {
                    let endLine = min(lines.count, index + 1 + contextAfter)
                    for i in (index + 1)..<endLine {
                        contextLines.append("\(i + 1): \(lines[i])")
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
}

// MARK: - Input/Output Types

/// Input structure for the grep operation.
@Generable
public struct GrepInput {
    /// The regular expression pattern to search for.
    @Guide(description: "Search pattern (regex)")
    public let pattern: String
    
    /// File pattern to search (e.g., "*.swift").
    @Guide(description: "File pattern (e.g., '*.swift')")
    public let filePattern: String
    
    /// Base directory to search from.
    @Guide(description: "Base directory")
    public let basePath: String
    
    /// Whether to ignore case ("true" or "false").
    @Guide(description: "Case insensitive: 'true' or 'false'")
    public let ignoreCase: String
    
    /// Number of lines to show before each match.
    @Guide(description: "Lines of context before match")
    public let contextBefore: Int
    
    /// Number of lines to show after each match.
    @Guide(description: "Lines of context after match")
    public let contextAfter: Int
}

/// A single grep match result.
public struct GrepMatch: Codable, Sendable {
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
public struct GrepOutput: Codable, Sendable, CustomStringConvertible {
    /// List of all matches found.
    public let matches: [GrepMatch]
    
    /// Number of files searched.
    public let filesSearched: Int
    
    /// Total number of matches found.
    public let totalMatches: Int
    
    /// The pattern that was searched.
    public let pattern: String
    
    /// The base path that was searched.
    public let basePath: String
    
    public init(
        matches: [GrepMatch],
        filesSearched: Int,
        totalMatches: Int,
        pattern: String,
        basePath: String
    ) {
        self.matches = matches
        self.filesSearched = filesSearched
        self.totalMatches = totalMatches
        self.pattern = pattern
        self.basePath = basePath
    }
    
    public var description: String {
        let header = """
        Grep Search [Found \(totalMatches) match(es) in \(filesSearched) file(s)]
        Pattern: \(pattern)
        Base: \(basePath)
        """
        
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
    }
}

// Make GrepOutput conform to PromptRepresentable
extension GrepOutput: PromptRepresentable {
    public var promptRepresentation: Prompt {
        Prompt(description)
    }
}