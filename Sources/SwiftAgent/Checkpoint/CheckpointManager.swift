//
//  CheckpointManager.swift
//  SwiftAgent
//
//  Created by SwiftAgent on 2025/01/15.
//

import Foundation

/// A manager for creating and restoring file checkpoints.
///
/// `CheckpointManager` allows you to track files, create snapshots of their state,
/// and restore them to previous states. This is useful for reverting changes
/// made by an LLM agent.
///
/// ## Usage
///
/// ```swift
/// let manager = CheckpointManager()
///
/// // Track files
/// try await manager.track("/path/to/file.swift")
///
/// // Create checkpoint
/// let checkpoint = try await manager.createCheckpoint(name: "before-refactoring")
///
/// // ... LLM makes changes ...
///
/// // Rewind to checkpoint
/// let restored = try await manager.rewind(to: checkpoint.id)
/// ```
public actor CheckpointManager {

    // MARK: - Types

    /// Information about a checkpoint.
    public struct CheckpointInfo: Sendable, Identifiable, Codable {
        /// Unique identifier for this checkpoint.
        public let id: String
        /// Human-readable name for this checkpoint.
        public let name: String
        /// When this checkpoint was created.
        public let timestamp: Date
        /// Snapshots of all tracked files at checkpoint time.
        public let fileSnapshots: [FileSnapshot]
        /// Custom metadata associated with this checkpoint.
        public let metadata: [String: String]

        public init(
            id: String,
            name: String,
            timestamp: Date,
            fileSnapshots: [FileSnapshot],
            metadata: [String: String]
        ) {
            self.id = id
            self.name = name
            self.timestamp = timestamp
            self.fileSnapshots = fileSnapshots
            self.metadata = metadata
        }
    }

    /// A snapshot of a file's content at a point in time.
    public struct FileSnapshot: Sendable, Codable {
        /// The path to the file.
        public let path: String
        /// The file's content at snapshot time.
        public let content: Data
        /// The file's modification date at snapshot time.
        public let originalModificationDate: Date

        public init(path: String, content: Data, originalModificationDate: Date) {
            self.path = path
            self.content = content
            self.originalModificationDate = originalModificationDate
        }
    }

    // MARK: - Properties

    /// Paths being tracked for checkpointing.
    private var trackedPaths: Set<String> = []

    /// All saved checkpoints, keyed by ID.
    private var checkpoints: [String: CheckpointInfo] = [:]

    /// Current state of tracked files (for change detection).
    private var currentFileStates: [String: FileSnapshot] = [:]

    /// File manager for file operations.
    private let fileManager: FileManager

    // MARK: - Initialization

    /// Creates a new checkpoint manager.
    public init(fileManager: FileManager = .default) {
        self.fileManager = fileManager
    }

    // MARK: - Tracking

    /// Adds a file or directory to the tracking list.
    ///
    /// - Parameter path: The path to track. Can be a file or directory.
    /// - Throws: `CheckpointError.pathNotFound` if the path doesn't exist.
    public func track(_ path: String) throws {
        guard fileManager.fileExists(atPath: path) else {
            throw CheckpointError.pathNotFound(path)
        }

        var isDirectory: ObjCBool = false
        fileManager.fileExists(atPath: path, isDirectory: &isDirectory)

        if isDirectory.boolValue {
            // Track all files in the directory
            try trackDirectory(path)
        } else {
            trackedPaths.insert(path)
            try captureCurrentState(for: path)
        }
    }

    /// Removes a path from tracking.
    ///
    /// - Parameter path: The path to stop tracking.
    public func untrack(_ path: String) {
        trackedPaths.remove(path)
        currentFileStates.removeValue(forKey: path)
    }

    /// Returns all currently tracked paths.
    public var allTrackedPaths: Set<String> {
        trackedPaths
    }

    // MARK: - Checkpointing

    /// Creates a checkpoint of all tracked files.
    ///
    /// - Parameters:
    ///   - name: A human-readable name for this checkpoint.
    ///   - metadata: Optional custom metadata to associate with the checkpoint.
    /// - Returns: Information about the created checkpoint.
    public func createCheckpoint(
        name: String,
        metadata: [String: String] = [:]
    ) throws -> CheckpointInfo {
        var snapshots: [FileSnapshot] = []

        for path in trackedPaths {
            do {
                let snapshot = try captureSnapshot(for: path)
                snapshots.append(snapshot)
            } catch {
                // Skip files that can't be read (might have been deleted)
                continue
            }
        }

        let info = CheckpointInfo(
            id: UUID().uuidString,
            name: name,
            timestamp: Date(),
            fileSnapshots: snapshots,
            metadata: metadata
        )

        checkpoints[info.id] = info
        return info
    }

    /// Returns all checkpoints, sorted by creation time.
    public func listCheckpoints() -> [CheckpointInfo] {
        Array(checkpoints.values).sorted { $0.timestamp < $1.timestamp }
    }

    /// Gets a checkpoint by its ID.
    ///
    /// - Parameter id: The checkpoint ID.
    /// - Returns: The checkpoint info, or nil if not found.
    public func getCheckpoint(_ id: String) -> CheckpointInfo? {
        checkpoints[id]
    }

    /// Gets a checkpoint by its name.
    ///
    /// - Parameter name: The checkpoint name.
    /// - Returns: The most recent checkpoint with that name, or nil if not found.
    public func getCheckpoint(named name: String) -> CheckpointInfo? {
        checkpoints.values
            .filter { $0.name == name }
            .sorted { $0.timestamp > $1.timestamp }
            .first
    }

    /// Deletes a checkpoint.
    ///
    /// - Parameter id: The ID of the checkpoint to delete.
    @discardableResult
    public func deleteCheckpoint(_ id: String) -> CheckpointInfo? {
        checkpoints.removeValue(forKey: id)
    }

    /// Deletes all checkpoints.
    public func clearAllCheckpoints() {
        checkpoints.removeAll()
    }

    // MARK: - Rewind

    /// Restores all files to their state at a checkpoint.
    ///
    /// - Parameter checkpointID: The ID of the checkpoint to restore.
    /// - Returns: Array of paths that were restored.
    /// - Throws: `CheckpointError.checkpointNotFound` if the checkpoint doesn't exist.
    @discardableResult
    public func rewind(to checkpointID: String) throws -> [String] {
        guard let checkpoint = checkpoints[checkpointID] else {
            throw CheckpointError.checkpointNotFound(checkpointID)
        }

        var restoredPaths: [String] = []

        for snapshot in checkpoint.fileSnapshots {
            do {
                try restoreFile(from: snapshot)
                restoredPaths.append(snapshot.path)
            } catch {
                throw CheckpointError.restoreFailed(snapshot.path, error)
            }
        }

        return restoredPaths
    }

    /// Restores a specific file to its state at a checkpoint.
    ///
    /// - Parameters:
    ///   - path: The path of the file to restore.
    ///   - checkpointID: The ID of the checkpoint.
    /// - Throws: `CheckpointError.checkpointNotFound` or `CheckpointError.fileNotInCheckpoint`.
    public func rewindFile(
        _ path: String,
        to checkpointID: String
    ) throws {
        guard let checkpoint = checkpoints[checkpointID] else {
            throw CheckpointError.checkpointNotFound(checkpointID)
        }

        guard let snapshot = checkpoint.fileSnapshots.first(where: { $0.path == path }) else {
            throw CheckpointError.fileNotInCheckpoint(path)
        }

        try restoreFile(from: snapshot)
    }

    /// Compares current file states with a checkpoint.
    ///
    /// - Parameter checkpointID: The ID of the checkpoint to compare against.
    /// - Returns: A diff showing which files changed, were added, or were deleted.
    public func diff(from checkpointID: String) throws -> CheckpointDiff {
        guard let checkpoint = checkpoints[checkpointID] else {
            throw CheckpointError.checkpointNotFound(checkpointID)
        }

        var modified: [String] = []
        var added: [String] = []
        var deleted: [String] = []

        let checkpointPaths = Set(checkpoint.fileSnapshots.map { $0.path })

        // Check for modified and deleted files
        for snapshot in checkpoint.fileSnapshots {
            if fileManager.fileExists(atPath: snapshot.path) {
                if let currentContent = try? Data(contentsOf: URL(fileURLWithPath: snapshot.path)),
                   currentContent != snapshot.content {
                    modified.append(snapshot.path)
                }
            } else {
                deleted.append(snapshot.path)
            }
        }

        // Check for added files
        for path in trackedPaths {
            if !checkpointPaths.contains(path) && fileManager.fileExists(atPath: path) {
                added.append(path)
            }
        }

        return CheckpointDiff(
            modified: modified,
            added: added,
            deleted: deleted
        )
    }

    // MARK: - Private Methods

    private func trackDirectory(_ path: String) throws {
        guard let enumerator = fileManager.enumerator(atPath: path) else {
            throw CheckpointError.pathNotFound(path)
        }

        while let file = enumerator.nextObject() as? String {
            let fullPath = (path as NSString).appendingPathComponent(file)
            var isDir: ObjCBool = false
            if fileManager.fileExists(atPath: fullPath, isDirectory: &isDir), !isDir.boolValue {
                trackedPaths.insert(fullPath)
                try? captureCurrentState(for: fullPath)
            }
        }
    }

    private func captureCurrentState(for path: String) throws {
        let snapshot = try captureSnapshot(for: path)
        currentFileStates[path] = snapshot
    }

    private func captureSnapshot(for path: String) throws -> FileSnapshot {
        let url = URL(fileURLWithPath: path)
        let data = try Data(contentsOf: url)
        let attributes = try fileManager.attributesOfItem(atPath: path)
        let modDate = attributes[.modificationDate] as? Date ?? Date()

        return FileSnapshot(
            path: path,
            content: data,
            originalModificationDate: modDate
        )
    }

    private func restoreFile(from snapshot: FileSnapshot) throws {
        let url = URL(fileURLWithPath: snapshot.path)

        // Create parent directories if needed
        let parentDir = url.deletingLastPathComponent()
        if !fileManager.fileExists(atPath: parentDir.path) {
            try fileManager.createDirectory(at: parentDir, withIntermediateDirectories: true)
        }

        try snapshot.content.write(to: url)
    }
}

// MARK: - CheckpointDiff

/// Represents the differences between a checkpoint and current state.
public struct CheckpointDiff: Sendable {
    /// Files that exist in both states but have different content.
    public let modified: [String]
    /// Files that exist now but didn't exist at checkpoint time.
    public let added: [String]
    /// Files that existed at checkpoint time but don't exist now.
    public let deleted: [String]

    /// Whether there are any differences.
    public var hasChanges: Bool {
        !modified.isEmpty || !added.isEmpty || !deleted.isEmpty
    }

    /// Total number of changed files.
    public var totalChanges: Int {
        modified.count + added.count + deleted.count
    }
}

// MARK: - CheckpointError

/// Errors that can occur during checkpoint operations.
public enum CheckpointError: Error, LocalizedError {
    /// The specified path does not exist.
    case pathNotFound(String)
    /// The specified checkpoint does not exist.
    case checkpointNotFound(String)
    /// The specified file is not in the checkpoint.
    case fileNotInCheckpoint(String)
    /// Failed to create a snapshot of a file.
    case snapshotFailed(String, Error)
    /// Failed to restore a file from snapshot.
    case restoreFailed(String, Error)

    public var errorDescription: String? {
        switch self {
        case .pathNotFound(let path):
            return "Path not found: \(path)"
        case .checkpointNotFound(let id):
            return "Checkpoint not found: \(id)"
        case .fileNotInCheckpoint(let path):
            return "File not in checkpoint: \(path)"
        case .snapshotFailed(let path, let error):
            return "Failed to snapshot \(path): \(error.localizedDescription)"
        case .restoreFailed(let path, let error):
            return "Failed to restore \(path): \(error.localizedDescription)"
        }
    }
}
