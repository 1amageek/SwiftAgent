//
//  SkillDiscovery.swift
//  SwiftAgent
//
//  Created by SwiftAgent on 2025/01/15.
//

import Foundation

/// Discovers skills from standard directories.
///
/// `SkillDiscovery` searches for skills in the following locations:
///
/// 1. `~/.agent/skills/` - User-level skills
/// 2. `./.agent/skills/` - Project-level skills (relative to current directory)
/// 3. `$AGENT_SKILLS_PATH` - Additional paths from environment variable (colon-separated)
///
/// ## Usage
///
/// ```swift
/// // Discover all skills from standard paths
/// let skills = try SkillDiscovery.discoverAll()
///
/// // Discover from a specific directory
/// let projectSkills = try SkillDiscovery.discover(in: "/path/to/skills")
/// ```
public struct SkillDiscovery: Sendable {

    // MARK: - Constants

    /// Standard skill discovery paths.
    public static let standardPaths: [String] = [
        "~/.agent/skills",      // User-level skills
        "./.agent/skills"       // Project-level skills
    ]

    /// Environment variable for additional paths.
    public static let environmentVariable = "AGENT_SKILLS_PATH"

    // MARK: - Discovery Methods

    /// Discovers all skills from standard paths.
    ///
    /// Searches in:
    /// 1. `~/.agent/skills/`
    /// 2. `./.agent/skills/`
    /// 3. Paths from `$AGENT_SKILLS_PATH`
    ///
    /// - Returns: Array of discovered skills (metadata only).
    /// - Note: Invalid skills are skipped with a warning.
    public static func discoverAll() throws -> [Skill] {
        var allSkills: [Skill] = []
        var seenNames: Set<String> = []

        for path in searchPaths() {
            let expandedPath = expandPath(path)

            guard FileManager.default.fileExists(atPath: expandedPath) else {
                continue
            }

            do {
                let skills = try discover(in: expandedPath)
                for skill in skills {
                    // Skip duplicates (first one wins)
                    if !seenNames.contains(skill.id) {
                        seenNames.insert(skill.id)
                        allSkills.append(skill)
                    }
                }
            } catch {
                // Log warning but continue with other paths
                #if DEBUG
                print("Warning: Failed to discover skills in \(expandedPath): \(error)")
                #endif
            }
        }

        return allSkills
    }

    /// Discovers skills from a specific directory.
    ///
    /// Each subdirectory containing a `SKILL.md` file is treated as a skill.
    ///
    /// - Parameter path: Directory to search for skills.
    /// - Returns: Array of discovered skills (metadata only).
    /// - Throws: `SkillError.skillDirectoryNotFound` if path doesn't exist.
    public static func discover(in path: String) throws -> [Skill] {
        let expandedPath = expandPath(path)

        // Check directory exists
        var isDirectory: ObjCBool = false
        guard FileManager.default.fileExists(atPath: expandedPath, isDirectory: &isDirectory),
              isDirectory.boolValue else {
            throw SkillError.skillDirectoryNotFound(path: expandedPath)
        }

        // List subdirectories
        let contents: [String]
        do {
            contents = try FileManager.default.contentsOfDirectory(atPath: expandedPath)
        } catch {
            throw SkillError.fileReadError(path: expandedPath, underlyingError: error)
        }

        var skills: [Skill] = []

        for item in contents.sorted() {
            let itemPath = (expandedPath as NSString).appendingPathComponent(item)

            // Skip hidden files/directories
            if item.hasPrefix(".") {
                continue
            }

            // Check if it's a valid skill directory
            if isSkillDirectory(itemPath) {
                do {
                    let skill = try SkillLoader.loadMetadata(from: itemPath)
                    skills.append(skill)
                } catch {
                    // Log warning but continue with other skills
                    #if DEBUG
                    print("Warning: Failed to load skill from \(itemPath): \(error)")
                    #endif
                }
            }
        }

        return skills
    }

    /// Gets all configured search paths.
    ///
    /// Includes standard paths and paths from environment variable.
    ///
    /// - Returns: Array of paths to search.
    public static func searchPaths() -> [String] {
        var paths = standardPaths

        // Add paths from environment variable
        if let envPaths = ProcessInfo.processInfo.environment[environmentVariable] {
            let additionalPaths = envPaths
                .split(separator: ":")
                .map { String($0) }
                .filter { !$0.isEmpty }
            paths.append(contentsOf: additionalPaths)
        }

        return paths
    }

    /// Checks if a directory is a valid skill directory.
    ///
    /// A valid skill directory contains a `SKILL.md` file.
    ///
    /// - Parameter path: Directory path to check.
    /// - Returns: `true` if directory contains SKILL.md.
    public static func isSkillDirectory(_ path: String) -> Bool {
        let expandedPath = expandPath(path)

        // Check it's a directory
        var isDirectory: ObjCBool = false
        guard FileManager.default.fileExists(atPath: expandedPath, isDirectory: &isDirectory),
              isDirectory.boolValue else {
            return false
        }

        // Check for SKILL.md
        let skillFilePath = (expandedPath as NSString).appendingPathComponent("SKILL.md")
        return FileManager.default.fileExists(atPath: skillFilePath)
    }

    // MARK: - Path Helpers

    /// Expands path with tilde and resolves relative paths.
    ///
    /// - Parameter path: Path to expand.
    /// - Returns: Expanded absolute path.
    public static func expandPath(_ path: String) -> String {
        var expanded = (path as NSString).expandingTildeInPath

        // Resolve relative paths
        if !expanded.hasPrefix("/") {
            let currentDirectory = FileManager.default.currentDirectoryPath
            expanded = (currentDirectory as NSString).appendingPathComponent(expanded)
        }

        // Standardize path
        return (expanded as NSString).standardizingPath
    }

    /// Validates that a skill exists at the given path.
    ///
    /// - Parameter path: Path to the skill directory.
    /// - Throws: `SkillError` if the skill is invalid.
    public static func validateSkill(at path: String) throws {
        let expandedPath = expandPath(path)

        guard isSkillDirectory(expandedPath) else {
            throw SkillError.skillDirectoryNotFound(path: expandedPath)
        }

        // Try to load metadata to validate format
        _ = try SkillLoader.loadMetadata(from: expandedPath)
    }
}

// MARK: - Convenience Extensions

extension SkillDiscovery {

    /// Discovers skills from the current working directory's `.agent/skills/` folder.
    ///
    /// - Returns: Array of project-level skills.
    public static func discoverProjectSkills() throws -> [Skill] {
        let projectPath = FileManager.default.currentDirectoryPath
        let skillsPath = (projectPath as NSString).appendingPathComponent(".agent/skills")

        guard FileManager.default.fileExists(atPath: skillsPath) else {
            return []
        }

        return try discover(in: skillsPath)
    }

    /// Discovers skills from the user's home directory `~/.agent/skills/` folder.
    ///
    /// - Returns: Array of user-level skills.
    public static func discoverUserSkills() throws -> [Skill] {
        let userPath = ("~/.agent/skills" as NSString).expandingTildeInPath

        guard FileManager.default.fileExists(atPath: userPath) else {
            return []
        }

        return try discover(in: userPath)
    }
}
