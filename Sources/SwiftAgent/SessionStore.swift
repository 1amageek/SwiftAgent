//
//  SessionStore.swift
//  SwiftAgent
//
//  Created by SwiftAgent on 2025/01/15.
//

import Foundation

/// A protocol for storing and retrieving agent sessions.
///
/// `SessionStore` provides persistence for agent sessions, allowing them
/// to be saved and resumed later.
///
/// ## Usage
///
/// ```swift
/// let store = FileSessionStore(directory: .documentsDirectory)
///
/// // Save a session
/// try await store.save(snapshot)
///
/// // Load a session
/// if let snapshot = try await store.load(id: sessionID) {
///     let session = try await Conversation.resume(from: snapshot)
/// }
/// ```
public protocol SessionStore: Sendable {

    /// Saves a session snapshot.
    ///
    /// - Parameter snapshot: The session snapshot to save.
    /// - Throws: An error if saving fails.
    func save(_ snapshot: SessionSnapshot) async throws

    /// Loads a session snapshot by ID.
    ///
    /// - Parameter id: The session ID.
    /// - Returns: The session snapshot, or nil if not found.
    /// - Throws: An error if loading fails.
    func load(id: String) async throws -> SessionSnapshot?

    /// Deletes a session by ID.
    ///
    /// - Parameter id: The session ID to delete.
    /// - Throws: An error if deletion fails.
    func delete(id: String) async throws

    /// Lists all stored session IDs.
    ///
    /// - Returns: Array of session IDs.
    /// - Throws: An error if listing fails.
    func listSessionIds() async throws -> [String]

    /// Checks if a session exists.
    ///
    /// - Parameter id: The session ID.
    /// - Returns: `true` if the session exists.
    func exists(id: String) async throws -> Bool
}

// MARK: - Default Implementation

extension SessionStore {

    public func exists(id: String) async throws -> Bool {
        let snapshot = try await load(id: id)
        return snapshot != nil
    }
}

// MARK: - Session Snapshot

/// A serializable snapshot of an agent session.
///
/// `SessionSnapshot` captures the state of a session for persistence.
public struct SessionSnapshot: Codable, Sendable, Identifiable {

    /// The session ID.
    public let id: String

    /// The transcript of the session.
    public let transcript: Transcript

    /// When the session was created.
    public let createdAt: Date

    /// When the session was last updated.
    public let updatedAt: Date

    /// Optional metadata for the session.
    public let metadata: [String: String]

    /// The parent session ID if this is a forked session.
    public let parentSessionID: String?

    /// Creates a session snapshot.
    public init(
        id: String,
        transcript: Transcript,
        createdAt: Date = Date(),
        updatedAt: Date = Date(),
        metadata: [String: String] = [:],
        parentSessionID: String? = nil
    ) {
        self.id = id
        self.transcript = transcript
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.metadata = metadata
        self.parentSessionID = parentSessionID
    }

    /// Creates an updated snapshot with the current time.
    public func updated(transcript: Transcript) -> SessionSnapshot {
        SessionSnapshot(
            id: id,
            transcript: transcript,
            createdAt: createdAt,
            updatedAt: Date(),
            metadata: metadata,
            parentSessionID: parentSessionID
        )
    }

    /// Creates an updated snapshot with additional metadata.
    public func withMetadata(_ newMetadata: [String: String]) -> SessionSnapshot {
        var combined = metadata
        for (key, value) in newMetadata {
            combined[key] = value
        }
        return SessionSnapshot(
            id: id,
            transcript: transcript,
            createdAt: createdAt,
            updatedAt: Date(),
            metadata: combined,
            parentSessionID: parentSessionID
        )
    }
}

// MARK: - File Session Store

/// A file-based session store.
///
/// Sessions are stored as JSON files in a specified directory.
public actor FileSessionStore: SessionStore {

    /// The directory where sessions are stored.
    private let directory: URL

    /// File manager for file operations.
    private let fileManager: FileManager

    /// JSON encoder for serialization.
    private let encoder: JSONEncoder

    /// JSON decoder for deserialization.
    private let decoder: JSONDecoder

    /// Creates a file session store.
    ///
    /// - Parameter directory: The directory for storing sessions.
    public init(directory: URL) {
        self.directory = directory
        self.fileManager = FileManager.default
        self.encoder = JSONEncoder()
        self.encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        self.encoder.dateEncodingStrategy = .iso8601
        self.decoder = JSONDecoder()
        self.decoder.dateDecodingStrategy = .iso8601
    }

    /// Creates a file session store with a default directory.
    public init() {
        let appSupport = FileManager.default.urls(
            for: .applicationSupportDirectory,
            in: .userDomainMask
        ).first!

        let sessionsDir = appSupport.appendingPathComponent("SwiftAgent/Sessions")
        self.init(directory: sessionsDir)
    }

    // MARK: - SessionStore Implementation

    public func save(_ snapshot: SessionSnapshot) async throws {
        try ensureDirectoryExists()

        let fileURL = sessionFileURL(for: snapshot.id)
        let data = try encoder.encode(snapshot)
        try data.write(to: fileURL, options: .atomic)
    }

    public func load(id: String) async throws -> SessionSnapshot? {
        let fileURL = sessionFileURL(for: id)

        guard fileManager.fileExists(atPath: fileURL.path) else {
            return nil
        }

        let data = try Data(contentsOf: fileURL)
        return try decoder.decode(SessionSnapshot.self, from: data)
    }

    public func delete(id: String) async throws {
        let fileURL = sessionFileURL(for: id)

        guard fileManager.fileExists(atPath: fileURL.path) else {
            return
        }

        try fileManager.removeItem(at: fileURL)
    }

    public func listSessionIds() async throws -> [String] {
        try ensureDirectoryExists()

        let contents = try fileManager.contentsOfDirectory(
            at: directory,
            includingPropertiesForKeys: [.isRegularFileKey],
            options: [.skipsHiddenFiles]
        )

        return contents
            .filter { $0.pathExtension == "json" }
            .map { $0.deletingPathExtension().lastPathComponent }
    }

    public func exists(id: String) async throws -> Bool {
        let fileURL = sessionFileURL(for: id)
        return fileManager.fileExists(atPath: fileURL.path)
    }

    // MARK: - Additional Methods

    /// Clears all stored sessions.
    public func clearAll() async throws {
        let ids = try await listSessionIds()
        for id in ids {
            try await delete(id: id)
        }
    }

    /// Gets the storage size in bytes.
    public func storageSize() async throws -> Int64 {
        try ensureDirectoryExists()

        let contents = try fileManager.contentsOfDirectory(
            at: directory,
            includingPropertiesForKeys: [.fileSizeKey],
            options: [.skipsHiddenFiles]
        )

        var totalSize: Int64 = 0
        for url in contents {
            let resourceValues = try url.resourceValues(forKeys: [.fileSizeKey])
            totalSize += Int64(resourceValues.fileSize ?? 0)
        }

        return totalSize
    }

    // MARK: - Private Methods

    private func sessionFileURL(for id: String) -> URL {
        directory.appendingPathComponent("\(id).json")
    }

    private func ensureDirectoryExists() throws {
        if !fileManager.fileExists(atPath: directory.path) {
            try fileManager.createDirectory(
                at: directory,
                withIntermediateDirectories: true,
                attributes: nil
            )
        }
    }
}

// MARK: - In-Memory Session Store

/// An in-memory session store for testing.
///
/// Sessions are stored in memory and not persisted across app launches.
public actor InMemorySessionStore: SessionStore {

    /// Stored sessions.
    private var sessions: [String: SessionSnapshot] = [:]

    /// Creates an empty in-memory store.
    public init() {}

    /// Creates an in-memory store with initial sessions.
    public init(sessions: [SessionSnapshot]) {
        self.sessions = Dictionary(
            uniqueKeysWithValues: sessions.map { ($0.id, $0) }
        )
    }

    // MARK: - SessionStore Implementation

    public func save(_ snapshot: SessionSnapshot) async throws {
        sessions[snapshot.id] = snapshot
    }

    public func load(id: String) async throws -> SessionSnapshot? {
        sessions[id]
    }

    public func delete(id: String) async throws {
        sessions.removeValue(forKey: id)
    }

    public func listSessionIds() async throws -> [String] {
        Array(sessions.keys)
    }

    public func exists(id: String) async throws -> Bool {
        sessions[id] != nil
    }

    // MARK: - Additional Methods

    /// Clears all stored sessions.
    public func clearAll() async {
        sessions.removeAll()
    }

    /// Gets the number of stored sessions.
    public var count: Int {
        sessions.count
    }
}

// MARK: - Session Store Utilities

extension SessionStore {

    /// Loads multiple sessions by their IDs.
    ///
    /// - Parameter ids: The session IDs to load.
    /// - Returns: Dictionary mapping IDs to snapshots.
    public func loadMultiple(ids: [String]) async throws -> [String: SessionSnapshot] {
        var results: [String: SessionSnapshot] = [:]
        for id in ids {
            if let snapshot = try await load(id: id) {
                results[id] = snapshot
            }
        }
        return results
    }

    /// Saves multiple sessions.
    ///
    /// - Parameter snapshots: The sessions to save.
    public func saveMultiple(_ snapshots: [SessionSnapshot]) async throws {
        for snapshot in snapshots {
            try await save(snapshot)
        }
    }

    /// Deletes sessions older than a given date.
    ///
    /// - Parameter date: Sessions updated before this date will be deleted.
    /// - Returns: Number of sessions deleted.
    @discardableResult
    public func deleteOlderThan(_ date: Date) async throws -> Int {
        let ids = try await listSessionIds()
        var deletedCount = 0

        for id in ids {
            if let snapshot = try await load(id: id) {
                if snapshot.updatedAt < date {
                    try await delete(id: id)
                    deletedCount += 1
                }
            }
        }

        return deletedCount
    }
}
