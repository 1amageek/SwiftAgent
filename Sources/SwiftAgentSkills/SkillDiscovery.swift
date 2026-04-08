//
//  SkillDiscovery.swift
//  SwiftAgent
//
//  Created by SwiftAgent on 2025/01/15.
//

import Foundation

/// Discovers skills from standard directories.
///
/// `SkillDiscovery` follows the same search strategy as `claw-code`.
/// Skills are discovered from project ancestors, config-home directories,
/// user-level directories, and legacy `commands/` roots.
public struct SkillDiscovery: Sendable {

    /// Environment variable for additional skill roots.
    public static let environmentVariable = "AGENT_SKILLS_PATH"

    /// Discovers all skills from ordered roots. Earlier roots win on conflicts.
    public static func discoverAll(
        cwd: String = FileManager.default.currentDirectoryPath
    ) throws -> [Skill] {
        var allSkills: [Skill] = []
        var seenNames: Set<String> = []

        for root in searchRoots(cwd: cwd) {
            guard FileManager.default.fileExists(atPath: root.path) else {
                continue
            }

            do {
                let skills = try discover(in: root)
                for skill in skills {
                    let key = skill.id.lowercased()
                    if seenNames.insert(key).inserted {
                        allSkills.append(skill)
                    }
                }
            } catch {
                #if DEBUG
                print("Warning: Failed to discover skills in \(root.path): \(error)")
                #endif
            }
        }

        return allSkills
    }

    /// Discovers skills from a specific root path using `skills/` semantics.
    public static func discover(in path: String) throws -> [Skill] {
        let expandedPath = expandPath(path)
        return try discover(in: SkillDiscoveryRoot(path: expandedPath, origin: .skillsDirectory))
    }

    /// Ordered list of concrete search paths.
    public static func searchPaths(
        cwd: String = FileManager.default.currentDirectoryPath
    ) -> [String] {
        searchRoots(cwd: cwd).map(\.path)
    }

    /// Ordered list of concrete discovery roots.
    public static func searchRoots(
        cwd: String = FileManager.default.currentDirectoryPath
    ) -> [SkillDiscoveryRoot] {
        var roots: [SkillDiscoveryRoot] = []
        let cwdURL = URL(fileURLWithPath: expandPath(cwd)).standardizedFileURL

        for ancestor in ancestors(of: cwdURL) {
            appendRoot(&roots, path: ancestor.appendingPathComponent(".claw/skills").path, origin: .skillsDirectory)
            appendRoot(&roots, path: ancestor.appendingPathComponent(".omc/skills").path, origin: .skillsDirectory)
            appendRoot(&roots, path: ancestor.appendingPathComponent(".agents/skills").path, origin: .skillsDirectory)
            appendRoot(&roots, path: ancestor.appendingPathComponent(".codex/skills").path, origin: .skillsDirectory)
            appendRoot(&roots, path: ancestor.appendingPathComponent(".claude/skills").path, origin: .skillsDirectory)
            appendRoot(&roots, path: ancestor.appendingPathComponent(".claw/commands").path, origin: .legacyCommandsDirectory)
            appendRoot(&roots, path: ancestor.appendingPathComponent(".codex/commands").path, origin: .legacyCommandsDirectory)
            appendRoot(&roots, path: ancestor.appendingPathComponent(".claude/commands").path, origin: .legacyCommandsDirectory)
        }

        if let clawConfigHome = ProcessInfo.processInfo.environment["CLAW_CONFIG_HOME"] {
            appendRoot(&roots, path: (clawConfigHome as NSString).appendingPathComponent("skills"), origin: .skillsDirectory)
            appendRoot(&roots, path: (clawConfigHome as NSString).appendingPathComponent("commands"), origin: .legacyCommandsDirectory)
        }

        if let codexHome = ProcessInfo.processInfo.environment["CODEX_HOME"] {
            appendRoot(&roots, path: (codexHome as NSString).appendingPathComponent("skills"), origin: .skillsDirectory)
            appendRoot(&roots, path: (codexHome as NSString).appendingPathComponent("commands"), origin: .legacyCommandsDirectory)
        }

        if let claudeConfigDir = ProcessInfo.processInfo.environment["CLAUDE_CONFIG_DIR"] {
            appendRoot(&roots, path: (claudeConfigDir as NSString).appendingPathComponent("skills"), origin: .skillsDirectory)
            appendRoot(&roots, path: (claudeConfigDir as NSString).appendingPathComponent("skills/omc-learned"), origin: .skillsDirectory)
            appendRoot(&roots, path: (claudeConfigDir as NSString).appendingPathComponent("commands"), origin: .legacyCommandsDirectory)
        }

        if let home = ProcessInfo.processInfo.environment["HOME"] {
            appendRoot(&roots, path: (home as NSString).appendingPathComponent(".claw/skills"), origin: .skillsDirectory)
            appendRoot(&roots, path: (home as NSString).appendingPathComponent(".omc/skills"), origin: .skillsDirectory)
            appendRoot(&roots, path: (home as NSString).appendingPathComponent(".claw/commands"), origin: .legacyCommandsDirectory)
            appendRoot(&roots, path: (home as NSString).appendingPathComponent(".codex/skills"), origin: .skillsDirectory)
            appendRoot(&roots, path: (home as NSString).appendingPathComponent(".codex/commands"), origin: .legacyCommandsDirectory)
            appendRoot(&roots, path: (home as NSString).appendingPathComponent(".claude/skills"), origin: .skillsDirectory)
            appendRoot(&roots, path: (home as NSString).appendingPathComponent(".claude/skills/omc-learned"), origin: .skillsDirectory)
            appendRoot(&roots, path: (home as NSString).appendingPathComponent(".claude/commands"), origin: .legacyCommandsDirectory)
        }

        if let envPaths = ProcessInfo.processInfo.environment[environmentVariable] {
            for path in envPaths.split(separator: ":").map(String.init).filter({ !$0.isEmpty }) {
                appendRoot(&roots, path: path, origin: .skillsDirectory)
            }
        }

        return roots
    }

    /// Checks whether a directory contains a standard `SKILL.md`.
    public static func isSkillDirectory(_ path: String) -> Bool {
        let expandedPath = expandPath(path)

        var isDirectory: ObjCBool = false
        guard FileManager.default.fileExists(atPath: expandedPath, isDirectory: &isDirectory),
              isDirectory.boolValue else {
            return false
        }

        let skillFilePath = (expandedPath as NSString).appendingPathComponent("SKILL.md")
        return FileManager.default.fileExists(atPath: skillFilePath)
    }

    /// Expands `~` and resolves relative paths.
    public static func expandPath(_ path: String) -> String {
        var expanded = (path as NSString).expandingTildeInPath
        if !expanded.hasPrefix("/") {
            expanded = (FileManager.default.currentDirectoryPath as NSString).appendingPathComponent(expanded)
        }
        return (expanded as NSString).standardizingPath
    }

    /// Validates that a skill exists at the given path.
    public static func validateSkill(at path: String) throws {
        _ = try SkillLoader.loadMetadata(from: expandPath(path))
    }

    public static func discoverProjectSkills() throws -> [Skill] {
        try discoverAll(cwd: FileManager.default.currentDirectoryPath)
    }

    public static func discoverUserSkills() throws -> [Skill] {
        let roots = searchRoots().filter { root in
            root.path.contains("/.claw/")
                || root.path.contains("/.codex/")
                || root.path.contains("/.claude/")
                || root.path.contains("/.omc/")
        }

        var skills: [Skill] = []
        var seenNames: Set<String> = []

        for root in roots {
            guard FileManager.default.fileExists(atPath: root.path) else {
                continue
            }
            let discovered = try discover(in: root)
            for skill in discovered {
                let key = skill.id.lowercased()
                if seenNames.insert(key).inserted {
                    skills.append(skill)
                }
            }
        }

        return skills
    }

    private static func discover(in root: SkillDiscoveryRoot) throws -> [Skill] {
        var isDirectory: ObjCBool = false
        guard FileManager.default.fileExists(atPath: root.path, isDirectory: &isDirectory),
              isDirectory.boolValue else {
            throw SkillError.skillDirectoryNotFound(path: root.path)
        }

        let contents: [String]
        do {
            contents = try FileManager.default.contentsOfDirectory(atPath: root.path)
        } catch {
            throw SkillError.fileReadError(path: root.path, underlyingError: error)
        }

        var skills: [Skill] = []

        for item in contents.sorted() {
            if item.hasPrefix(".") {
                continue
            }

            let itemPath = (root.path as NSString).appendingPathComponent(item)
            let candidatePath: String?

            switch root.origin {
            case .skillsDirectory:
                candidatePath = isSkillDirectory(itemPath) ? itemPath : nil
            case .legacyCommandsDirectory:
                if isSkillDirectory(itemPath) {
                    candidatePath = itemPath
                } else if itemPath.lowercased().hasSuffix(".md") {
                    candidatePath = itemPath
                } else {
                    candidatePath = nil
                }
            }

            guard let candidatePath else {
                continue
            }

            do {
                skills.append(try SkillLoader.loadMetadata(from: candidatePath))
            } catch {
                #if DEBUG
                print("Warning: Failed to load skill from \(candidatePath): \(error)")
                #endif
            }
        }

        return skills
    }

    private static func appendRoot(
        _ roots: inout [SkillDiscoveryRoot],
        path: String,
        origin: SkillOrigin
    ) {
        let root = SkillDiscoveryRoot(path: expandPath(path), origin: origin)
        if !roots.contains(root) {
            roots.append(root)
        }
    }

    private static func ancestors(of url: URL) -> [URL] {
        var result: [URL] = []
        var current = url
        while true {
            result.append(current)
            let parent = current.deletingLastPathComponent()
            if parent.path == current.path {
                break
            }
            current = parent
        }
        return result
    }
}
