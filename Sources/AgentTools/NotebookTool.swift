//
//  NotebookTool.swift
//  AgentTools
//
//  In-memory key-value scratchpad tool.
//

import Foundation
import SwiftAgent

/// A tool for storing and retrieving data in an in-memory scratchpad.
///
/// `NotebookTool` provides a key-value store that persists for the duration of a session,
/// enabling LLMs to save intermediate results outside their context window.
///
/// ## Operations
/// - `write`: Store a value by key (overwrites existing)
/// - `read`: Retrieve a value by key (supports offset/limit pagination)
/// - `append`: Add text to an existing key's value
/// - `list`: Show all stored keys
/// - `delete`: Remove a key
public struct NotebookTool: Tool {
    public typealias Arguments = NotebookInput
    public typealias Output = NotebookOutput

    public static let name = "Notebook"
    public var name: String { Self.name }

    /// Default number of lines to return for read operations.
    public static let defaultLineLimit = 200

    public static let description = """
    In-memory key-value scratchpad for storing and retrieving data outside the context window.

    Usage:
    - Use this to save intermediate results, accumulate data across multiple steps, or store large content that would otherwise consume context
    - Data persists only for the current session and is shared with sub-sessions created by Dispatch
    - When dealing with large data, store it in Notebook and have Dispatch sub-tasks read from it

    Operations:
    - "write": Store a value by key (overwrites existing)
    - "read": Retrieve a value by key (supports offset/limit for large values)
    - "append": Add text to an existing key's value
    - "list": Show all stored keys with their sizes
    - "delete": Remove a key

    When to use:
    - Intermediate results from multi-step analysis
    - Large data that would fill up the context window
    - Shared data between parent and Dispatch sub-sessions
    - Accumulating results from parallel Dispatch queries
    """

    public var description: String { Self.description }

    public var parameters: GenerationSchema {
        NotebookInput.generationSchema
    }

    private let storage: NotebookStorage

    /// Creates a NotebookTool with the given storage.
    ///
    /// - Parameter storage: The shared storage instance. Defaults to a new instance.
    public init(storage: NotebookStorage = NotebookStorage()) {
        self.storage = storage
    }

    public func call(arguments: NotebookInput) async throws -> NotebookOutput {
        switch arguments.operation.lowercased() {
        case "write":
            return try performWrite(key: arguments.key, value: arguments.value)
        case "read":
            return try performRead(key: arguments.key, offset: arguments.offset, limit: arguments.limit)
        case "append":
            return try performAppend(key: arguments.key, value: arguments.value)
        case "list":
            return performList()
        case "delete":
            return try performDelete(key: arguments.key)
        default:
            throw NotebookError.invalidOperation(arguments.operation)
        }
    }

    // MARK: - Operations

    private func performWrite(key: String, value: String) throws -> NotebookOutput {
        guard !key.isEmpty else {
            throw NotebookError.emptyKey
        }
        guard value.utf8.count <= NotebookStorage.maxValueSize else {
            throw NotebookError.valueTooLarge(
                size: value.utf8.count,
                limit: NotebookStorage.maxValueSize
            )
        }
        storage.write(key: key, value: value)
        return NotebookOutput(
            success: true,
            content: "Written \(value.count) characters to key '\(key)'.",
            key: key,
            operation: "write"
        )
    }

    private func performRead(key: String, offset: Int, limit: Int) throws -> NotebookOutput {
        guard !key.isEmpty else {
            throw NotebookError.emptyKey
        }
        guard let value = storage.read(key: key) else {
            throw NotebookError.keyNotFound(key)
        }

        let lines = value.components(separatedBy: .newlines)
        let totalLines = lines.count

        let startOffset = max(0, offset)
        let lineLimit = limit > 0 ? limit : Self.defaultLineLimit

        let startLine = startOffset + 1
        let endLine = min(startOffset + lineLimit, totalLines)

        guard startLine <= totalLines else {
            return NotebookOutput(
                success: true,
                content: "(empty - offset beyond content)",
                key: key,
                operation: "read",
                totalLines: totalLines,
                linesRead: 0
            )
        }

        var formattedLines: [String] = []
        for lineNum in startLine...endLine {
            let lineIndex = lineNum - 1
            if lineIndex < lines.count {
                formattedLines.append("\(lineNum)→\(lines[lineIndex])")
            }
        }

        let content = formattedLines.joined(separator: "\n")
        return NotebookOutput(
            success: true,
            content: content,
            key: key,
            operation: "read",
            totalLines: totalLines,
            linesRead: formattedLines.count
        )
    }

    private func performAppend(key: String, value: String) throws -> NotebookOutput {
        guard !key.isEmpty else {
            throw NotebookError.emptyKey
        }

        // Check size after append
        let currentSize = storage.read(key: key)?.utf8.count ?? 0
        guard currentSize + value.utf8.count <= NotebookStorage.maxValueSize else {
            throw NotebookError.valueTooLarge(
                size: currentSize + value.utf8.count,
                limit: NotebookStorage.maxValueSize
            )
        }

        storage.append(key: key, value: value)
        return NotebookOutput(
            success: true,
            content: "Appended \(value.count) characters to key '\(key)'.",
            key: key,
            operation: "append"
        )
    }

    private func performList() -> NotebookOutput {
        let keys = storage.list()
        let content: String
        if keys.isEmpty {
            content = "(no keys stored)"
        } else {
            content = keys.enumerated()
                .map { "\($0.offset + 1). \($0.element)" }
                .joined(separator: "\n")
        }
        return NotebookOutput(
            success: true,
            content: content,
            key: "",
            operation: "list"
        )
    }

    private func performDelete(key: String) throws -> NotebookOutput {
        guard !key.isEmpty else {
            throw NotebookError.emptyKey
        }
        let deleted = storage.delete(key: key)
        if deleted {
            return NotebookOutput(
                success: true,
                content: "Deleted key '\(key)'.",
                key: key,
                operation: "delete"
            )
        } else {
            throw NotebookError.keyNotFound(key)
        }
    }
}

// MARK: - Input/Output Types

/// Input structure for notebook operations.
@Generable
public struct NotebookInput: Sendable {
    @Guide(description: "Operation: write, read, append, list, delete", .anyOf(["write", "read", "append", "list", "delete"]))
    public let operation: String

    @Guide(description: "Key name (required for write, read, append, delete)")
    public let key: String

    @Guide(description: "Value to write or append (required for write, append)")
    public let value: String

    @Guide(description: "Line offset for read (0-based, default: 0)")
    public let offset: Int

    @Guide(description: "Number of lines to read (default: 200)")
    public let limit: Int
}

/// Output structure for notebook operations.
public struct NotebookOutput: Sendable {
    public let success: Bool
    public let content: String
    public let key: String
    public let operation: String
    public let totalLines: Int
    public let linesRead: Int

    public init(
        success: Bool,
        content: String,
        key: String,
        operation: String,
        totalLines: Int = 0,
        linesRead: Int = 0
    ) {
        self.success = success
        self.content = content
        self.key = key
        self.operation = operation
        self.totalLines = totalLines
        self.linesRead = linesRead
    }
}

extension NotebookOutput: PromptRepresentable {
    public var promptRepresentation: Prompt {
        Prompt(description)
    }
}

extension NotebookOutput: CustomStringConvertible {
    public var description: String {
        let status = success ? "Success" : "Failed"
        let lineInfo = linesRead > 0 ? " (lines: \(linesRead) of \(totalLines))" : ""
        return """
        Notebook [\(status)] \(operation)\(key.isEmpty ? "" : " key='\(key)'")\(lineInfo)

        \(content)
        """
    }
}

// MARK: - Errors

/// Errors that can occur during notebook operations.
public enum NotebookError: LocalizedError {
    case keyNotFound(String)
    case invalidOperation(String)
    case emptyKey
    case valueTooLarge(size: Int, limit: Int)

    public var errorDescription: String? {
        switch self {
        case .keyNotFound(let key):
            return "Key not found: '\(key)'"
        case .invalidOperation(let op):
            return "Invalid operation: '\(op)'. Valid operations: write, read, append, list, delete"
        case .emptyKey:
            return "Key cannot be empty"
        case .valueTooLarge(let size, let limit):
            return "Value too large: \(size) bytes (limit: \(limit) bytes)"
        }
    }
}
