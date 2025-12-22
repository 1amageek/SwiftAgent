//
//  Skill.swift
//  SwiftAgent
//
//  Created by SwiftAgent on 2025/01/15.
//

import Foundation

/// A loaded skill with metadata and instructions.
///
/// Skills are loaded in two phases following the progressive disclosure model:
///
/// 1. **Discovery Phase**: Only metadata is loaded (`instructions` is nil).
///    This keeps context usage minimal during startup.
///
/// 2. **Activation Phase**: Full instructions are loaded when the skill is activated.
///
/// ## Directory Structure
///
/// ```
/// skill-name/
/// ├── SKILL.md          # Required: metadata + instructions
/// ├── scripts/          # Optional: executable code
/// ├── references/       # Optional: additional documentation
/// └── assets/           # Optional: templates, resources
/// ```
public struct Skill: Identifiable, Sendable, Equatable {

    // MARK: - Properties

    /// Unique identifier (same as name).
    public var id: String { metadata.name }

    /// Skill metadata from frontmatter.
    public let metadata: SkillMetadata

    /// Full instructions (Markdown body).
    ///
    /// This is `nil` if only metadata has been loaded (discovery phase).
    /// Call `SkillLoader.loadFull()` to load the full instructions.
    public let instructions: String?

    /// Absolute path to the skill directory.
    public let directoryPath: String

    // MARK: - Computed Properties

    /// Path to SKILL.md file.
    public var skillFilePath: String {
        (directoryPath as NSString).appendingPathComponent("SKILL.md")
    }

    /// Path to scripts directory.
    public var scriptsPath: String {
        (directoryPath as NSString).appendingPathComponent("scripts")
    }

    /// Path to references directory.
    public var referencesPath: String {
        (directoryPath as NSString).appendingPathComponent("references")
    }

    /// Path to assets directory.
    public var assetsPath: String {
        (directoryPath as NSString).appendingPathComponent("assets")
    }

    /// Whether the skill has a scripts directory.
    public var hasScripts: Bool {
        FileManager.default.fileExists(atPath: scriptsPath)
    }

    /// Whether the skill has a references directory.
    public var hasReferences: Bool {
        FileManager.default.fileExists(atPath: referencesPath)
    }

    /// Whether the skill has an assets directory.
    public var hasAssets: Bool {
        FileManager.default.fileExists(atPath: assetsPath)
    }

    /// Whether the skill is fully loaded (has instructions).
    public var isFullyLoaded: Bool {
        instructions != nil
    }

    // MARK: - Initialization

    /// Creates a skill.
    ///
    /// - Parameters:
    ///   - metadata: The skill metadata.
    ///   - instructions: The full instructions (nil for discovery phase).
    ///   - directoryPath: Absolute path to the skill directory.
    public init(
        metadata: SkillMetadata,
        instructions: String? = nil,
        directoryPath: String
    ) {
        self.metadata = metadata
        self.instructions = instructions
        self.directoryPath = directoryPath
    }

    // MARK: - Resource Access

    /// Gets the absolute path to a resource within the skill.
    ///
    /// - Parameter relativePath: Path relative to the skill directory.
    /// - Returns: Absolute path to the resource.
    public func resourcePath(_ relativePath: String) -> String {
        (directoryPath as NSString).appendingPathComponent(relativePath)
    }

    /// Checks if a resource exists within the skill.
    ///
    /// - Parameter relativePath: Path relative to the skill directory.
    /// - Returns: `true` if the resource exists.
    public func resourceExists(_ relativePath: String) -> Bool {
        FileManager.default.fileExists(atPath: resourcePath(relativePath))
    }

    /// Lists files in a skill subdirectory.
    ///
    /// - Parameter subdirectory: The subdirectory name (e.g., "scripts", "references").
    /// - Returns: Array of file names in the subdirectory.
    public func listResources(in subdirectory: String) -> [String] {
        let path = resourcePath(subdirectory)
        guard let contents = try? FileManager.default.contentsOfDirectory(atPath: path) else {
            return []
        }
        return contents.sorted()
    }

    // MARK: - Equatable

    public static func == (lhs: Skill, rhs: Skill) -> Bool {
        lhs.metadata == rhs.metadata &&
        lhs.instructions == rhs.instructions &&
        lhs.directoryPath == rhs.directoryPath
    }
}

// MARK: - CustomStringConvertible

extension Skill: CustomStringConvertible {

    public var description: String {
        let loaded = isFullyLoaded ? "loaded" : "metadata-only"
        return "Skill(\(metadata.name), \(loaded))"
    }
}

// MARK: - Hashable

extension Skill: Hashable {

    public func hash(into hasher: inout Hasher) {
        hasher.combine(id)
        hasher.combine(directoryPath)
    }
}
