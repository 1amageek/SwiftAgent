//
//  EditTool.swift
//  SwiftAgent
//
//  Created by SwiftAgent on 2025/01/09.
//

import Foundation
import OpenFoundationModels
import SwiftAgent

/// A tool for editing existing files by finding and replacing text.
///
/// `EditTool` provides controlled file editing with search and replace functionality,
/// supporting both single and multiple replacements.
///
/// ## Features
/// - Find and replace text in files
/// - Single or all occurrences replacement
/// - Preview changes before applying
/// - Atomic write operations
///
/// ## Limitations
/// - Maximum file size: 1MB
/// - UTF-8 encoding only
/// - Text files only
public struct EditTool: OpenFoundationModels.Tool {
    public typealias Arguments = EditInput
    public typealias Output = EditOutput
    
    public static let name = "edit"
    public var name: String { Self.name }
    
    public static let description = """
    Edits existing files by finding and replacing text.
    
    Use this tool to:
    - Fix bugs by replacing code
    - Update configuration values
    - Refactor variable or function names
    
    Features:
    - Find and replace text
    - Replace first occurrence or all
    - Preview changes
    
    Limitations:
    - File must exist
    - Maximum file size: 1MB
    - Text files only
    """
    
    public var description: String { Self.description }
    
    private let workingDirectory: String
    private let fsActor: FileSystemActor
    
    public init(workingDirectory: String = FileManager.default.currentDirectoryPath) {
        self.workingDirectory = workingDirectory
        self.fsActor = FileSystemActor(workingDirectory: workingDirectory)
    }
    
    public func call(arguments: EditInput) async throws -> EditOutput {
        // Validate inputs
        guard !arguments.oldString.isEmpty else {
            throw FileSystemError.operationFailed(reason: "oldString cannot be empty")
        }
        
        guard arguments.oldString != arguments.newString else {
            throw FileSystemError.operationFailed(reason: "oldString and newString are identical")
        }
        
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
        
        // Parse replaceAll flag with strict validation
        let replaceAll: Bool
        switch arguments.replaceAll.lowercased() {
        case "true":
            replaceAll = true
        case "false":
            replaceAll = false
        default:
            throw FileSystemError.operationFailed(
                reason: "replaceAll must be 'true' or 'false', got: '\(arguments.replaceAll)'"
            )
        }
        
        // Perform replacement
        let newContent: String
        let replacementCount: Int
        
        if replaceAll {
            // Replace all occurrences
            newContent = originalContent.replacingOccurrences(
                of: arguments.oldString,
                with: arguments.newString
            )
            
            // Count replacements
            let originalOccurrences = originalContent.components(separatedBy: arguments.oldString).count - 1
            replacementCount = originalOccurrences
        } else {
            // Replace first occurrence only
            if let range = originalContent.range(of: arguments.oldString) {
                newContent = originalContent.replacingCharacters(
                    in: range,
                    with: arguments.newString
                )
                replacementCount = 1
            } else {
                newContent = originalContent
                replacementCount = 0
            }
        }
        
        // Check if any changes were made
        guard replacementCount > 0 else {
            return EditOutput(
                success: false,
                replacements: 0,
                path: normalizedPath,
                preview: "No occurrences of '\(arguments.oldString)' found in file",
                message: "No changes made"
            )
        }
        
        // Write the modified content back
        try await fsActor.writeFile(content: newContent, toPath: normalizedPath)
        
        // Generate preview of changes
        let preview = generatePreview(
            oldString: arguments.oldString,
            newString: arguments.newString,
            replacements: replacementCount
        )
        
        return EditOutput(
            success: true,
            replacements: replacementCount,
            path: normalizedPath,
            preview: preview,
            message: "Successfully replaced \(replacementCount) occurrence(s)"
        )
    }
    
    private func generatePreview(oldString: String, newString: String, replacements: Int) -> String {
        let oldPreview = String(oldString.prefix(50))
        let newPreview = String(newString.prefix(50))
        
        let oldSuffix = oldString.count > 50 ? "..." : ""
        let newSuffix = newString.count > 50 ? "..." : ""
        
        return """
        Replaced \(replacements) occurrence(s):
        Old: "\(oldPreview)\(oldSuffix)"
        New: "\(newPreview)\(newSuffix)"
        """
    }
}

// MARK: - Input/Output Types

/// Input structure for the edit operation.
@Generable
public struct EditInput: Sendable {
    /// The file path to edit.
    @Guide(description: "File path to edit")
    public let path: String
    
    /// The text to find in the file.
    @Guide(description: "Text to find")
    public let oldString: String
    
    /// The text to replace it with.
    @Guide(description: "Text to replace with")
    public let newString: String
    
    /// Whether to replace all occurrences ("true" or "false").
    @Guide(description: "Replace all occurrences: 'true' or 'false'")
    public let replaceAll: String
}

/// Output structure for the edit operation.
public struct EditOutput: Codable, Sendable, CustomStringConvertible {
    /// Whether the operation was successful.
    public let success: Bool
    
    /// Number of replacements made.
    public let replacements: Int
    
    /// The file path that was edited.
    public let path: String
    
    /// Preview of the changes made.
    public let preview: String
    
    /// A descriptive message about the operation.
    public let message: String
    
    public init(
        success: Bool,
        replacements: Int,
        path: String,
        preview: String,
        message: String
    ) {
        self.success = success
        self.replacements = replacements
        self.path = path
        self.preview = preview
        self.message = message
    }
    
    public var description: String {
        """
        Edit Operation [\(success ? "Success" : "Failed")]
        Path: \(path)
        \(message)
        
        \(preview)
        """
    }
}

// Make EditOutput conform to PromptRepresentable
extension EditOutput: PromptRepresentable {
    public var promptRepresentation: Prompt {
        Prompt(description)
    }
}