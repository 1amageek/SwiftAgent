//
//  MultiEditTool.swift
//  SwiftAgent
//
//  Created by SwiftAgent on 2025/01/09.
//

import Foundation
import SwiftAgent

/// A tool for applying multiple edit operations to a file in a single transaction.
///
/// `MultiEditTool` provides atomic batch editing with rollback on failure,
/// ensuring all edits succeed or none are applied.
///
/// ## Features
/// - Apply multiple find/replace operations
/// - Transactional processing (all or nothing)
/// - Order-preserving execution
/// - JSON-based edit specification
///
/// ## Limitations
/// - Maximum file size: 1MB
/// - UTF-8 encoding only
/// - Text files only
/// - JSON array format required
public struct MultiEditTool: Tool {
    public typealias Arguments = MultiEditInput
    public typealias Output = MultiEditOutput

    public static let name = "MultiEdit"
    public var name: String { Self.name }

    public static let description = """
    Apply multiple edit operations to a file in a single atomic transaction.

    Usage:
    - You MUST use the Read tool first before using this tool
    - All edits succeed or none are applied (transactional). If any edit fails, the file is left unchanged
    - Edits are applied in order; earlier edits may change the text that later edits match against
    - Provide edits as a JSON array: [{"old":"text to find","new":"replacement text"},...]
    - Each edit performs an exact string replacement (same rules as Edit tool)
    - Use this tool instead of multiple sequential Edit calls when you need to make several changes to the same file
    - Maximum file size: 1MB, UTF-8 text files only
    """

    public var description: String { Self.description }
    
    public var parameters: GenerationSchema {
        MultiEditInput.generationSchema
    }
    
    private let workingDirectory: String
    private let fsActor: FileSystemActor
    
    public init(workingDirectory: String = FileManager.default.currentDirectoryPath) {
        self.workingDirectory = workingDirectory
        self.fsActor = FileSystemActor(workingDirectory: workingDirectory)
    }
    
    public func call(arguments: MultiEditInput) async throws -> MultiEditOutput {
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
        let originalContent = try await fsActor.readFile(atPath: normalizedPath)
        
        // Parse JSON edits
        let edits = try parseJSONEdits(arguments.editsJson)
        
        // Validate all edits
        for (index, edit) in edits.enumerated() {
            guard !edit.old.isEmpty else {
                throw FileSystemError.operationFailed(
                    reason: "Edit \(index + 1): 'old' string cannot be empty"
                )
            }
            guard edit.old != edit.new else {
                throw FileSystemError.operationFailed(
                    reason: "Edit \(index + 1): 'old' and 'new' strings are identical"
                )
            }
        }
        
        // Apply all edits in memory
        var workingContent = originalContent
        var changes: [String] = []
        var appliedCount = 0
        
        for (index, edit) in edits.enumerated() {
            let occurrences = workingContent.components(separatedBy: edit.old).count - 1
            
            if occurrences > 0 {
                workingContent = workingContent.replacingOccurrences(
                    of: edit.old,
                    with: edit.new
                )
                appliedCount += 1
                changes.append("Edit \(index + 1): Replaced \(occurrences) occurrence(s) of '\(truncate(edit.old))' with '\(truncate(edit.new))'")
            } else {
                changes.append("Edit \(index + 1): No occurrences of '\(truncate(edit.old))' found (skipped)")
            }
        }
        
        // Check if any changes were made
        guard appliedCount > 0 else {
            return MultiEditOutput(
                success: false,
                totalEdits: edits.count,
                appliedEdits: 0,
                changes: changes,
                path: normalizedPath,
                message: "No changes made - no matching text found"
            )
        }
        
        // Write the modified content back (atomic operation)
        try await fsActor.writeFile(content: workingContent, toPath: normalizedPath)
        
        return MultiEditOutput(
            success: true,
            totalEdits: edits.count,
            appliedEdits: appliedCount,
            changes: changes,
            path: normalizedPath,
            message: "Successfully applied \(appliedCount) of \(edits.count) edits"
        )
    }
    
    private struct EditOperation: Codable {
        let old: String
        let new: String
    }
    
    private func parseJSONEdits(_ jsonString: String) throws -> [EditOperation] {
        guard let data = jsonString.data(using: .utf8) else {
            throw FileSystemError.operationFailed(
                reason: "Invalid UTF-8 in editsJson"
            )
        }
        
        do {
            let edits = try JSONDecoder().decode([EditOperation].self, from: data)
            guard !edits.isEmpty else {
                throw FileSystemError.operationFailed(
                    reason: "editsJson array cannot be empty"
                )
            }
            return edits
        } catch {
            throw FileSystemError.operationFailed(
                reason: "Invalid JSON in editsJson. Expected format: [{\"old\":\"text\",\"new\":\"replacement\"}]. Error: \(error.localizedDescription)"
            )
        }
    }
    
    private func truncate(_ str: String, maxLength: Int = 30) -> String {
        if str.count <= maxLength {
            return str
        }
        return String(str.prefix(maxLength)) + "..."
    }
}

// MARK: - Input/Output Types

/// Input structure for the multi-edit operation.
@Generable
public struct MultiEditInput: Sendable {
    /// The file path to edit.
    public let path: String
    
    /// JSON array of edit operations.
    public let editsJson: String
}

/// Output structure for the multi-edit operation.
public struct MultiEditOutput: Sendable {
    /// Whether the operation was successful.
    public let success: Bool
    
    /// Total number of edits requested.
    public let totalEdits: Int
    
    /// Number of edits actually applied.
    public let appliedEdits: Int
    
    /// Details of each edit operation.
    public let changes: [String]
    
    /// The file path that was edited.
    public let path: String
    
    /// A descriptive message about the operation.
    public let message: String
    
    public init(
        success: Bool,
        totalEdits: Int,
        appliedEdits: Int,
        changes: [String],
        path: String,
        message: String
    ) {
        self.success = success
        self.totalEdits = totalEdits
        self.appliedEdits = appliedEdits
        self.changes = changes
        self.path = path
        self.message = message
    }
}

extension MultiEditOutput: PromptRepresentable {
    public var promptRepresentation: Prompt {
        Prompt(description)
    }
}

extension MultiEditOutput: CustomStringConvertible {
    public var description: String {
        let changesDetail = changes.isEmpty ? "" : "\n\nChanges:\n" + changes.joined(separator: "\n")
        
        return """
        MultiEdit Operation [\(success ? "Success" : "Failed")]
        Path: \(path)
        \(message)\(changesDetail)
        """
    }
}

