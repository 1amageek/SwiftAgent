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

    public static let name = "edit"
    public var name: String { Self.name }

    public static let description = """
    Replace exact string in file. Fails if old_string not unique (use replace_all=true for multiple). \
    Preserve exact indentation. Max 1MB, UTF-8 only.
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
        guard !arguments.old_string.isEmpty else {
            throw FileSystemError.operationFailed(reason: "old_string cannot be empty")
        }

        guard arguments.old_string != arguments.new_string else {
            throw FileSystemError.operationFailed(reason: "old_string and new_string must be different")
        }

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
        let originalContent = try await fsActor.readFile(atPath: normalizedPath)

        // Count occurrences of old_string
        let occurrenceCount = originalContent.components(separatedBy: arguments.old_string).count - 1

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
        if !arguments.replace_all && occurrenceCount > 1 {
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

        if arguments.replace_all {
            // Replace all occurrences
            newContent = originalContent.replacingOccurrences(
                of: arguments.old_string,
                with: arguments.new_string
            )
            replacementCount = occurrenceCount
        } else {
            // Replace first (and only) occurrence
            if let range = originalContent.range(of: arguments.old_string) {
                newContent = originalContent.replacingCharacters(
                    in: range,
                    with: arguments.new_string
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
            oldString: arguments.old_string,
            newString: arguments.new_string,
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
    @Guide(description: "File path to modify")
    public let file_path: String

    @Guide(description: "Exact text to find and replace")
    public let old_string: String

    @Guide(description: "Replacement text")
    public let new_string: String

    @Guide(description: "Replace all occurrences (default: false)")
    public let replace_all: Bool
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

