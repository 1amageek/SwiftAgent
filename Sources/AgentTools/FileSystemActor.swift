//
//  FileSystemActor.swift
//  SwiftAgent
//
//  Created by SwiftAgent on 2025/01/09.
//

import Foundation

/// An actor to ensure thread-safe file system operations shared across multiple tools.
public actor FileSystemActor {
    // MARK: - Constants
    
    /// Maximum file size for read/write operations (1MB)
    public static let maxFileSize: Int64 = 1024 * 1024
    
    /// Default file encoding
    public static let defaultEncoding: String.Encoding = .utf8
    
    // MARK: - Properties
    
    private let workingDirectory: String
    
    // MARK: - Initialization
    
    /// Creates a new FileSystemActor instance.
    ///
    /// - Parameter workingDirectory: The base directory for all file operations.
    public init(workingDirectory: String = FileManager.default.currentDirectoryPath) {
        self.workingDirectory = workingDirectory
    }
    
    // MARK: - Path Operations
    
    /// Normalizes a file path to an absolute path.
    ///
    /// - Parameter path: The path to normalize.
    /// - Returns: The normalized absolute path.
    public func normalizePath(_ path: String) -> String {
        let expandedPath = NSString(string: path).expandingTildeInPath
        let absolutePath: String
        
        if expandedPath.hasPrefix("/") {
            absolutePath = expandedPath
        } else {
            absolutePath = URL(fileURLWithPath: workingDirectory)
                .appendingPathComponent(expandedPath).path
        }
        
        return URL(fileURLWithPath: absolutePath).standardized.path
    }
    
    /// Checks if a path is safe (within the working directory).
    ///
    /// - Parameter path: The path to validate.
    /// - Returns: `true` if the path is safe, `false` otherwise.
    public func isPathSafe(_ path: String) -> Bool {
        // Resolve symbolic links for both paths to prevent escape via symlinks
        let pathURL = URL(fileURLWithPath: path)
        let workingDirURL = URL(fileURLWithPath: workingDirectory)
        
        let resolvedPath = pathURL.resolvingSymlinksInPath().standardized.path
        let resolvedWorkingDir = workingDirURL.resolvingSymlinksInPath().standardized.path
        
        // Ensure the resolved path starts with the resolved working directory
        return resolvedPath.hasPrefix(resolvedWorkingDir + "/") || resolvedPath == resolvedWorkingDir
    }
    
    // MARK: - File Existence
    
    /// Checks if a file exists at the given path.
    ///
    /// - Parameter path: The path to check.
    /// - Returns: `true` if the file exists, `false` otherwise.
    public func fileExists(atPath path: String) -> Bool {
        FileManager.default.fileExists(atPath: path)
    }
    
    /// Checks if a path exists and determines if it's a directory.
    ///
    /// - Parameters:
    ///   - path: The path to check.
    ///   - isDirectory: A pointer to a boolean that will be set to indicate if the path is a directory.
    /// - Returns: `true` if the path exists, `false` otherwise.
    public func fileExists(atPath path: String, isDirectory: inout ObjCBool) -> Bool {
        FileManager.default.fileExists(atPath: path, isDirectory: &isDirectory)
    }
    
    // MARK: - File Attributes
    
    /// Gets file attributes for the given path.
    ///
    /// - Parameter path: The file path.
    /// - Returns: A dictionary of file attributes, or nil if the file doesn't exist.
    public func fileAttributes(atPath path: String) -> [FileAttributeKey: Any]? {
        try? FileManager.default.attributesOfItem(atPath: path)
    }
    
    /// Gets the file size for the given path.
    ///
    /// - Parameter path: The file path.
    /// - Returns: The file size in bytes, or nil if the file doesn't exist.
    public func fileSize(atPath path: String) -> Int64? {
        fileAttributes(atPath: path)?[.size] as? Int64
    }
    
    /// Checks if a file is a binary file by examining its contents.
    ///
    /// - Parameter data: The file data to check.
    /// - Returns: `true` if the file appears to be binary, `false` otherwise.
    public func isBinaryData(_ data: Data) -> Bool {
        let sampleSize = min(data.count, 1024)
        let sample = data.prefix(sampleSize)
        
        // Check for null bytes or non-text control characters
        return sample.contains { byte in
            byte == 0 || (byte < 32 && byte != 9 && byte != 10 && byte != 13)
        }
    }
    
    // MARK: - Directory Operations
    
    /// Creates a directory at the specified path.
    ///
    /// - Parameter path: The directory path to create.
    /// - Throws: An error if the directory cannot be created.
    public func createDirectory(atPath path: String) throws {
        try FileManager.default.createDirectory(
            atPath: path,
            withIntermediateDirectories: true,
            attributes: nil
        )
    }
    
    /// Lists the contents of a directory.
    ///
    /// - Parameter path: The directory path.
    /// - Returns: An array of file names in the directory.
    /// - Throws: An error if the directory cannot be read.
    public func listDirectory(atPath path: String) throws -> [String] {
        try FileManager.default.contentsOfDirectory(atPath: path)
    }
    
    
    // MARK: - File Information
    
    /// Gets detailed information about a file or directory.
    ///
    /// - Parameter path: The file or directory path.
    /// - Returns: A formatted string with file information.
    public func getFileInfo(atPath path: String) -> String {
        let fileManager = FileManager.default
        
        do {
            let attributes = try fileManager.attributesOfItem(atPath: path)
            let fileName = URL(fileURLWithPath: path).lastPathComponent
            
            let fileType = attributes[.type] as? FileAttributeType
            let fileSize = attributes[.size] as? Int64 ?? 0
            let modificationDate = attributes[.modificationDate] as? Date
            
            let typeString: String
            switch fileType {
            case .typeDirectory:
                typeString = "d"
            case .typeRegular:
                typeString = "-"
            case .typeSymbolicLink:
                typeString = "l"
            default:
                typeString = "?"
            }
            
            let sizeString = fileType == .typeDirectory ? "-" : formatFileSize(fileSize)
            let dateString = modificationDate?.formatted(
                .dateTime.year().month().day().hour().minute()
            ) ?? "Unknown"
            
            return "\(typeString) \(sizeString.padding(toLength: 10, withPad: " ", startingAt: 0)) \(dateString) \(fileName)"
        } catch {
            return "? Error \(URL(fileURLWithPath: path).lastPathComponent)"
        }
    }
    
    /// Formats a file size for display.
    ///
    /// - Parameter size: The size in bytes.
    /// - Returns: A formatted size string.
    private func formatFileSize(_ size: Int64) -> String {
        let formatter = ByteCountFormatter()
        formatter.countStyle = .file
        return formatter.string(fromByteCount: size)
    }
    
    // MARK: - File Operations
    
    /// Reads a file as UTF-8 text.
    ///
    /// - Parameter path: The file path to read.
    /// - Returns: The file contents as a string.
    /// - Throws: An error if the file cannot be read.
    public func readFile(atPath path: String) throws -> String {
        let data = try Data(contentsOf: URL(fileURLWithPath: path))
        
        // Check file size limit
        if data.count > Self.maxFileSize {
            throw FileSystemError.fileTooLarge(size: Int64(data.count), limit: Self.maxFileSize)
        }
        
        // Check for binary data
        if isBinaryData(data) {
            throw FileSystemError.binaryFileDetected
        }
        
        // Decode as UTF-8
        guard let content = String(data: data, encoding: Self.defaultEncoding) else {
            throw FileSystemError.invalidEncoding
        }
        
        return content
    }
    
    /// Writes text to a file atomically.
    ///
    /// - Parameters:
    ///   - content: The text content to write.
    ///   - path: The file path to write to.
    /// - Throws: An error if the file cannot be written.
    public func writeFile(content: String, toPath path: String) throws {
        guard let data = content.data(using: Self.defaultEncoding) else {
            throw FileSystemError.invalidEncoding
        }
        
        // Check size limit
        if data.count > Self.maxFileSize {
            throw FileSystemError.contentTooLarge(size: Int64(data.count), limit: Self.maxFileSize)
        }
        
        let url = URL(fileURLWithPath: path)
        
        // Create parent directory if needed
        let directory = url.deletingLastPathComponent().path
        if !directory.isEmpty && !fileExists(atPath: directory) {
            try createDirectory(atPath: directory)
        }
        
        // Write atomically to prevent partial writes
        try data.write(to: url, options: .atomic)
    }
    
    /// Deletes a file at the specified path.
    ///
    /// - Parameter path: The file path to delete.
    /// - Throws: An error if the file cannot be deleted.
    public func deleteFile(atPath path: String) throws {
        try FileManager.default.removeItem(atPath: path)
    }
    
    /// Copies a file from source to destination.
    ///
    /// - Parameters:
    ///   - source: The source file path.
    ///   - destination: The destination file path.
    /// - Throws: An error if the file cannot be copied.
    public func copyFile(from source: String, to destination: String) throws {
        try FileManager.default.copyItem(atPath: source, toPath: destination)
    }
    
    /// Moves a file from source to destination.
    ///
    /// - Parameters:
    ///   - source: The source file path.
    ///   - destination: The destination file path.
    /// - Throws: An error if the file cannot be moved.
    public func moveFile(from source: String, to destination: String) throws {
        try FileManager.default.moveItem(atPath: source, toPath: destination)
    }
}

// MARK: - FileSystemError

/// Errors that can occur during file system operations.
public enum FileSystemError: LocalizedError {
    case pathNotSafe(path: String)
    case fileNotFound(path: String)
    case fileTooLarge(size: Int64, limit: Int64)
    case contentTooLarge(size: Int64, limit: Int64)
    case binaryFileDetected
    case invalidEncoding
    case notADirectory(path: String)
    case notAFile(path: String)
    case permissionDenied(path: String)
    case operationFailed(reason: String)
    
    public var errorDescription: String? {
        switch self {
        case .pathNotSafe(let path):
            return "Path is not within working directory: \(path)"
        case .fileNotFound(let path):
            return "File not found: \(path)"
        case .fileTooLarge(let size, let limit):
            return "File too large: \(size) bytes (limit: \(limit) bytes)"
        case .contentTooLarge(let size, let limit):
            return "Content too large: \(size) bytes (limit: \(limit) bytes)"
        case .binaryFileDetected:
            return "Cannot process binary file as text"
        case .invalidEncoding:
            return "Invalid UTF-8 encoding"
        case .notADirectory(let path):
            return "Path is not a directory: \(path)"
        case .notAFile(let path):
            return "Path is not a file: \(path)"
        case .permissionDenied(let path):
            return "Permission denied: \(path)"
        case .operationFailed(let reason):
            return "Operation failed: \(reason)"
        }
    }
}