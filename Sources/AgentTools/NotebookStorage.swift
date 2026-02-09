//
//  NotebookStorage.swift
//  AgentTools
//
//  In-memory key-value storage for Notebook tool.
//

import Foundation
import Synchronization

/// Thread-safe in-memory key-value storage for the Notebook tool.
///
/// `NotebookStorage` provides a scratchpad for storing data outside the LLM's
/// context window. Data persists only for the lifetime of the storage instance
/// (typically one session).
///
/// Uses `Mutex` instead of `actor` because all operations are pure in-memory
/// dictionary access with no I/O or suspension points.
///
/// ## Usage
///
/// ```swift
/// let storage = NotebookStorage()
/// storage.write(key: "analysis", value: "Results of the analysis...")
/// if let value = storage.read(key: "analysis") {
///     print(value)
/// }
/// ```
public final class NotebookStorage: Sendable {

    /// Maximum value size in bytes (1MB).
    public static let maxValueSize = 1024 * 1024

    // MARK: - State

    private struct State: Sendable {
        var storage: [String: String] = [:]
    }

    private let state = Mutex(State())

    // MARK: - Initialization

    public init() {}

    // MARK: - Operations

    /// Writes a value for the given key, overwriting any existing value.
    ///
    /// - Parameters:
    ///   - key: The key to store the value under.
    ///   - value: The value to store.
    public func write(key: String, value: String) {
        state.withLock { $0.storage[key] = value }
    }

    /// Reads the value for the given key.
    ///
    /// - Parameter key: The key to read.
    /// - Returns: The stored value, or `nil` if the key does not exist.
    public func read(key: String) -> String? {
        state.withLock { $0.storage[key] }
    }

    /// Appends text to the value for the given key.
    ///
    /// If the key does not exist, creates it with the given value.
    ///
    /// - Parameters:
    ///   - key: The key to append to.
    ///   - value: The text to append.
    public func append(key: String, value: String) {
        state.withLock { $0.storage[key, default: ""] += value }
    }

    /// Returns all keys in sorted order.
    ///
    /// - Returns: A sorted array of all stored keys.
    public func list() -> [String] {
        state.withLock { $0.storage.keys.sorted() }
    }

    /// Deletes the value for the given key.
    ///
    /// - Parameter key: The key to delete.
    /// - Returns: `true` if the key existed and was deleted, `false` otherwise.
    @discardableResult
    public func delete(key: String) -> Bool {
        state.withLock { $0.storage.removeValue(forKey: key) != nil }
    }

    /// Returns the number of stored keys.
    public var count: Int {
        state.withLock { $0.storage.count }
    }
}
