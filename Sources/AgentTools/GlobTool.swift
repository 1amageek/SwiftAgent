//
//  GlobTool.swift
//  SwiftAgent
//
//  Created by SwiftAgent on 2025/01/09.
//

import Foundation
import OpenFoundationModels
import SwiftAgent

/// A tool for searching files using glob patterns.
///
/// `GlobTool` provides file system traversal with pattern matching,
/// supporting wildcards and recursive directory search.
///
/// ## Features
/// - Glob pattern matching (*, **, ?)
/// - File type filtering (files, directories, or both)
/// - Recursive directory traversal
/// - Sorted results
///
/// ## Pattern Syntax
/// - `*` matches any characters except path separator
/// - `**` matches any characters including path separators (recursive)
/// - `?` matches single character
/// - `*.swift` matches all Swift files
/// - `**/*.md` matches all Markdown files recursively
public struct GlobTool: OpenFoundationModels.Tool {
    public typealias Arguments = GlobInput
    public typealias Output = GlobOutput
    
    public static let name = "glob"
    public var name: String { Self.name }
    
    public static let description = """
    Searches for files using glob patterns.
    
    Use this tool to:
    - Find files by extension (*.swift)
    - Search recursively (**/*.md)
    - List directory contents
    
    Pattern syntax:
    - * matches any characters (except /)
    - ** matches recursively
    - ? matches single character
    
    Examples:
    - "*.swift" - Swift files in current dir
    - "**/*.md" - All markdown files recursively
    - "src/**/*.ts" - TypeScript files under src/
    """
    
    public var description: String { Self.description }
    
    private let workingDirectory: String
    private let fsActor: FileSystemActor
    
    public init(workingDirectory: String = FileManager.default.currentDirectoryPath) {
        self.workingDirectory = workingDirectory
        self.fsActor = FileSystemActor(workingDirectory: workingDirectory)
    }
    
    public func call(arguments: GlobInput) async throws -> GlobOutput {
        // Normalize and validate base path
        let normalizedBasePath = await fsActor.normalizePath(arguments.basePath)
        guard await fsActor.isPathSafe(normalizedBasePath) else {
            throw FileSystemError.pathNotSafe(path: arguments.basePath)
        }
        
        // Check if base path exists and is a directory
        var isDirectory: ObjCBool = false
        guard await fsActor.fileExists(atPath: normalizedBasePath, isDirectory: &isDirectory) else {
            throw FileSystemError.fileNotFound(path: normalizedBasePath)
        }
        
        guard isDirectory.boolValue else {
            throw FileSystemError.notADirectory(path: normalizedBasePath)
        }
        
        // Parse file type filter
        let fileType = try parseFileType(arguments.fileType)
        
        // Search for matching files
        let matches = try await findMatches(
            pattern: arguments.pattern,
            basePath: normalizedBasePath,
            fileType: fileType
        )
        
        // Sort results
        let sortedMatches = matches.sorted()
        
        return GlobOutput(
            files: sortedMatches,
            count: sortedMatches.count,
            pattern: arguments.pattern,
            basePath: normalizedBasePath
        )
    }
    
    private func parseFileType(_ typeString: String) throws -> FileType {
        switch typeString.lowercased() {
        case "file", "f":
            return .file
        case "directory", "dir", "d":
            return .directory
        case "any", "all", "":
            return .any
        default:
            throw FileSystemError.operationFailed(
                reason: "fileType must be 'file', 'dir', or 'any', got: '\(typeString)'"
            )
        }
    }
    
    private func findMatches(pattern: String, basePath: String, fileType: FileType) async throws -> [String] {
        // Determine if pattern requires recursive search
        let isRecursive = pattern.contains("**")
        
        // Convert glob pattern to regex
        let regex = try globToRegex(pattern)
        
        // Perform synchronous file enumeration in a detached Task
        let results: [String] = try await Task<[String], Error>.detached { [regex, basePath, isRecursive, fileType] in
            var results: [String] = []
            
            // Get file enumerator
            let enumeratorOptions: FileManager.DirectoryEnumerationOptions = isRecursive ? [] : [.skipsSubdirectoryDescendants]
            
            let fileManager = FileManager.default
            guard let enumerator = fileManager.enumerator(
                at: URL(fileURLWithPath: basePath),
                includingPropertiesForKeys: [.isDirectoryKey, .isRegularFileKey],
                options: enumeratorOptions.union([.skipsHiddenFiles])
            ) else {
                return []
            }
            
            // Iterate through files using nextObject() for memory efficiency
            while let object = enumerator.nextObject() {
                guard let fileURL = object as? URL else { continue }
                
                // Get relative path from base
                let relativePath = fileURL.path.replacingOccurrences(of: basePath + "/", with: "")
                
                // Check if path matches pattern
                if relativePath.range(of: regex, options: .regularExpression) != nil {
                    // Check file type filter
                    let resourceValues = try fileURL.resourceValues(forKeys: [.isDirectoryKey, .isRegularFileKey])
                    let isDir = resourceValues.isDirectory ?? false
                    
                    let matchesType: Bool
                    switch fileType {
                    case .file:
                        matchesType = !isDir
                    case .directory:
                        matchesType = isDir
                    case .any:
                        matchesType = true
                    }
                    
                    if matchesType {
                        results.append(fileURL.path)
                    }
                }
            }
            
            return results
        }.value
        
        // Filter results for safe paths
        var safeResults: [String] = []
        for path in results {
            if await fsActor.isPathSafe(path) {
                safeResults.append(path)
            }
        }
        
        return safeResults
    }
    
    private func globToRegex(_ glob: String) throws -> String {
        var regex = "^"
        var i = 0
        let chars = Array(glob)
        
        while i < chars.count {
            let char = chars[i]
            
            switch char {
            case "*":
                // Check for **
                if i + 1 < chars.count && chars[i + 1] == "*" {
                    regex += ".*"  // ** matches everything including /
                    i += 1  // Skip next *
                } else {
                    regex += "[^/]*"  // * matches everything except /
                }
                
            case "?":
                regex += "[^/]"  // ? matches single char except /
                
            case "[":
                // Character class - find closing ]
                var j = i + 1
                var foundClose = false
                while j < chars.count {
                    if chars[j] == "]" {
                        foundClose = true
                        break
                    }
                    j += 1
                }
                
                if foundClose {
                    // Copy character class as-is
                    regex += String(chars[i...j])
                    i = j
                } else {
                    // No closing ], treat as literal [
                    regex += "\\["
                }
                
            case ".", "+", "(", ")", "^", "$", "{", "}", "|", "\\":
                // Escape regex special characters
                regex += "\\\(char)"
                
            default:
                regex += String(char)
            }
            
            i += 1
        }
        
        regex += "$"
        return regex
    }
    
    private enum FileType {
        case file
        case directory
        case any
    }
}

// MARK: - Input/Output Types

/// Input structure for the glob operation.
@Generable
public struct GlobInput: Sendable {
    /// The glob pattern to match files against.
    @Guide(description: "Glob pattern (e.g., '*.swift', '**/*.md')")
    public let pattern: String
    
    /// The base directory to search from.
    @Guide(description: "Base directory (default: current)")
    public let basePath: String
    
    /// File type filter: "file", "dir", or "any".
    @Guide(description: "File type: 'file', 'dir', or 'any'")
    public let fileType: String
}

/// Output structure for the glob operation.
public struct GlobOutput: Codable, Sendable, CustomStringConvertible {
    /// List of matching file paths.
    public let files: [String]
    
    /// Number of matching files.
    public let count: Int
    
    /// The pattern that was searched.
    public let pattern: String
    
    /// The base path that was searched.
    public let basePath: String
    
    public init(
        files: [String],
        count: Int,
        pattern: String,
        basePath: String
    ) {
        self.files = files
        self.count = count
        self.pattern = pattern
        self.basePath = basePath
    }
    
    public var description: String {
        let filesList = files.isEmpty ? "No matches found" : files.joined(separator: "\n")
        
        return """
        Glob Search [Found \(count) match(es)]
        Pattern: \(pattern)
        Base: \(basePath)
        
        \(filesList)
        """
    }
}

// Make GlobOutput conform to PromptRepresentable
extension GlobOutput: PromptRepresentable {
    public var promptRepresentation: Prompt {
        Prompt(description)
    }
}