//
//  EditTool.swift
//  SwiftAgent
//
//  Created by SwiftAgent on 2025/01/09.
//

import Foundation
import OpenFoundationModels
import SwiftAgent

/// A tool for performing exact string replacements in files.
///
/// `EditTool` provides controlled file editing with search and replace functionality,
/// supporting both single and multiple replacements.
///
/// ## Features
/// - Exact string replacement (not regex)
/// - Uniqueness validation (fails if old_string is not unique unless replace_all is true)
/// - Replace single or all occurrences
/// - Atomic write operations
///
/// ## Usage
/// - Provide the exact text to find (old_string) and replacement (new_string)
/// - The edit will FAIL if old_string is not unique (appears multiple times)
/// - Use replace_all to change every instance if that's intended
/// - Always preserve exact indentation when matching code
///
/// ## Limitations
/// - Maximum file size: 1MB
/// - UTF-8 encoding only
/// - Text files only
public struct EditTool: OpenFoundationModels.Tool {
    public typealias Arguments = EditInput
    public typealias Output = EditOutput

    public static let name = "file_edit"
    public var name: String { Self.name }

    public static let description = """
    Performs exact string replacements in files.

    Usage:
    - Provide old_string with exact text to replace (including indentation)
    - The edit will FAIL if old_string is not unique in the file
    - Either provide more surrounding context to make it unique, or use replace_all=true
    - Use replace_all for renaming variables/functions across the file

    Important:
    - Preserve exact indentation (tabs/spaces) when matching code
    - old_string and new_string must be different
    - ALWAYS prefer editing existing files over creating new ones

    Limitations:
    - File must exist
    - Maximum file size: 1MB
    - Text files only (UTF-8)
    """

    public var description: String { Self.description }

    public var parameters: GenerationSchema {
        EditInput.generationSchema
    }

    private let workingDirectory: String
    private let fsActor: FileSystemActor

    public init(workingDirectory: String = FileManager.default.currentDirectoryPath) {
        self.workingDirectory = workingDirectory
        self.fsActor = FileSystemActor(workingDirectory: workingDirectory)
    }

    public func call(arguments: EditInput) async throws -> EditOutput {
        // Validate inputs
        guard !arguments.oldString.isEmpty else {
            throw FileSystemError.operationFailed(reason: "old_string cannot be empty")
        }

        guard arguments.oldString != arguments.newString else {
            throw FileSystemError.operationFailed(reason: "old_string and new_string must be different")
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

        // Count occurrences of old_string
        let occurrenceCount = originalContent.components(separatedBy: arguments.oldString).count - 1

        // Check if old_string exists in file
        guard occurrenceCount > 0 else {
            return EditOutput(
                success: false,
                replacements: 0,
                path: normalizedPath,
                preview: "No occurrences of the specified text found in file",
                message: "No changes made - old_string not found"
            )
        }

        // If not replace_all and multiple occurrences, fail with helpful message
        if !arguments.replaceAll && occurrenceCount > 1 {
            return EditOutput(
                success: false,
                replacements: 0,
                path: normalizedPath,
                preview: "Found \(occurrenceCount) occurrences of the text",
                message: "Edit FAILED: old_string is not unique (\(occurrenceCount) occurrences found). Either provide a larger string with more surrounding context to make it unique, or use replace_all=true to change every instance."
            )
        }

        // Perform replacement
        let newContent: String
        let replacementCount: Int

        if arguments.replaceAll {
            // Replace all occurrences
            newContent = originalContent.replacingOccurrences(
                of: arguments.oldString,
                with: arguments.newString
            )
            replacementCount = occurrenceCount
        } else {
            // Replace first (and only) occurrence
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
        let oldPreview = String(oldString.prefix(100))
        let newPreview = String(newString.prefix(100))

        let oldSuffix = oldString.count > 100 ? "..." : ""
        let newSuffix = newString.count > 100 ? "..." : ""

        return """
        Replaced \(replacements) occurrence(s):
        - Old: "\(oldPreview)\(oldSuffix)"
        + New: "\(newPreview)\(newSuffix)"
        """
    }
}

// MARK: - Input/Output Types

/// Input structure for the edit operation.
@Generable
public struct EditInput: Sendable {
    @Guide(description: "The absolute path to the file to modify")
    public let path: String

    @Guide(description: "The exact text to replace (must match exactly, including whitespace)")
    public let oldString: String

    @Guide(description: "The text to replace it with (must be different from old_string)")
    public let newString: String

    @Guide(description: "Replace all occurrences of old_string. Default is false. Set to true when renaming variables or making bulk changes.")
    public let replaceAll: Bool
}

/// Output structure for the edit operation.
public struct EditOutput: Sendable {
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
}

extension EditOutput: PromptRepresentable {
    public var promptRepresentation: Prompt {
        Prompt(description)
    }
}

extension EditOutput: CustomStringConvertible {
    public var description: String {
        """
        Edit Operation [\(success ? "Success" : "Failed")]
        Path: \(path)
        \(message)
        
        \(preview)
        """
    }
}

