//
//  SkillLoader.swift
//  SwiftAgent
//
//  Created by SwiftAgent on 2025/01/15.
//

import Foundation
import SwiftSkill

/// Loads and parses SKILL.md files.
///
/// Supports two formats:
///
/// **Format 1: YAML Frontmatter**
/// ```markdown
/// ---
/// name: skill-name
/// description: What this skill does
/// ---
/// # Instructions
/// ```
///
/// **Format 2: Plain Markdown** (Claude Code / Codex compatible)
/// ```markdown
/// # Skill Title
///
/// Description paragraph.
///
/// ## When to Use
/// - ...
/// ```
public struct SkillLoader: Sendable {

    // MARK: - Public Methods

    /// Loads only metadata from a SKILL.md file or legacy markdown skill (discovery phase).
    ///
    /// This is efficient for startup when we only need name and description
    /// to build the `<available_skills>` prompt.
    ///
    /// - Parameter directoryPath: Path to the skill directory or markdown file.
    /// - Returns: Skill with metadata only (instructions = nil).
    /// - Throws: `SkillError` if loading fails.
    public static func loadMetadata(from directoryPath: String) throws -> Skill {
        let source = try resolveSource(at: directoryPath)
        let content = try readSkillFile(at: source.promptFilePath)

        // Detect format and parse
        let rawMetadata: SkillMetadata
        if hasFrontmatter(content) {
            (rawMetadata, _) = try parseFrontmatter(content, fallbackName: source.fallbackName)
        } else {
            (rawMetadata, _) = try parseMarkdownSkill(content, fallbackName: source.fallbackName)
        }
        let metadata = normalizeDirectoryNameIfNeeded(rawMetadata, source: source)

        // Validate metadata
        try metadata.validate(directoryName: source.expectedDirectoryName)

        return Skill(
            metadata: metadata,
            instructions: nil,
            directoryPath: source.directoryPath,
            promptFilePath: source.promptFilePath
        )
    }

    /// Loads full skill including instructions (activation phase).
    ///
    /// - Parameter directoryPath: Path to the skill directory or markdown file.
    /// - Returns: Skill with full instructions.
    /// - Throws: `SkillError` if loading fails.
    public static func loadFull(from directoryPath: String) throws -> Skill {
        let source = try resolveSource(at: directoryPath)
        let content = try readSkillFile(at: source.promptFilePath)

        // Detect format and parse
        let rawMetadata: SkillMetadata
        let body: String
        if hasFrontmatter(content) {
            (rawMetadata, body) = try parseFrontmatter(content, fallbackName: source.fallbackName)
        } else {
            (rawMetadata, body) = try parseMarkdownSkill(content, fallbackName: source.fallbackName)
        }
        let metadata = normalizeDirectoryNameIfNeeded(rawMetadata, source: source)

        // Validate metadata
        try metadata.validate(directoryName: source.expectedDirectoryName)

        return Skill(
            metadata: metadata,
            instructions: body.trimmingCharacters(in: .whitespacesAndNewlines),
            directoryPath: source.directoryPath,
            promptFilePath: source.promptFilePath
        )
    }

    /// Loads full skill from a skill that only has metadata.
    ///
    /// - Parameter skill: A skill with metadata only.
    /// - Returns: Skill with full instructions.
    /// - Throws: `SkillError` if loading fails.
    public static func loadFull(from skill: Skill) throws -> Skill {
        if skill.isFullyLoaded {
            return skill
        }
        let sourcePath = ((skill.promptFilePath as NSString).lastPathComponent == "SKILL.md")
            ? skill.directoryPath
            : skill.promptFilePath
        return try loadFull(from: sourcePath)
    }

    // MARK: - Format Detection

    /// Checks whether the content starts with YAML frontmatter delimiters.
    private static func hasFrontmatter(_ content: String) -> Bool {
        let firstLine = content.prefix(while: { $0 != "\n" && $0 != "\r" })
        return firstLine.trimmingCharacters(in: .whitespaces) == "---"
    }

    // MARK: - Plain Markdown Parsing

    /// Parses a plain Markdown SKILL.md (Claude Code / Codex format).
    ///
    /// Extracts:
    /// - `name` from the directory name
    /// - `description` from the first paragraph after the title heading
    /// - `body` is the entire file content
    ///
    /// - Parameters:
    ///   - content: Raw SKILL.md file content.
    ///   - fallbackName: Directory or file-stem fallback used as the skill name.
    /// - Returns: Tuple of (metadata, body).
    /// - Throws: `SkillError.invalidFormat` if content is empty.
    static func parseMarkdownSkill(
        _ content: String,
        fallbackName: String
    ) throws -> (metadata: SkillMetadata, body: String) {
        let trimmed = content.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            throw SkillError.invalidFormat(reason: "SKILL.md is empty")
        }

        let lines = trimmed.components(separatedBy: .newlines)

        // Extract description: first non-empty paragraph after skipping headings
        var descriptionLines: [String] = []
        var foundDescription = false
        for line in lines {
            let stripped = line.trimmingCharacters(in: .whitespaces)

            // Skip heading lines
            if stripped.hasPrefix("#") {
                if foundDescription { break }
                continue
            }

            // Skip empty lines before description starts
            if stripped.isEmpty {
                if foundDescription { break }
                continue
            }

            // Collect description paragraph lines
            descriptionLines.append(stripped)
            foundDescription = true
        }

        let description = descriptionLines.isEmpty
            ? fallbackName
            : descriptionLines.joined(separator: " ")

        let metadata = SkillMetadata(
            name: fallbackName,
            description: description
        )

        return (metadata, content)
    }

    // MARK: - Frontmatter Parsing

    /// Parses YAML frontmatter from SKILL.md content.
    ///
    /// - Parameter content: Raw SKILL.md file content.
    /// - Returns: Tuple of (metadata, body).
    /// - Throws: `SkillError.invalidFormat` if parsing fails.
    public static func parseFrontmatter(_ content: String) throws -> (metadata: SkillMetadata, body: String) {
        do {
            let skill = try SkillParser().parse(content)
            return (metadata: SkillMetadata(skill: skill), body: skill.body)
        } catch {
            throw SkillError.frontmatterParsingError(reason: error.localizedDescription)
        }
    }

    private static func parseFrontmatter(
        _ content: String,
        fallbackName: String
    ) throws -> (metadata: SkillMetadata, body: String) {
        do {
            return try parseFrontmatter(content)
        } catch {
            return try parseFrontmatterFallback(content, fallbackName: fallbackName, originalError: error)
        }
    }

    private static func parseFrontmatterFallback(
        _ content: String,
        fallbackName: String,
        originalError: Error
    ) throws -> (metadata: SkillMetadata, body: String) {
        let lines = content.components(separatedBy: .newlines)
        guard lines.first?.trimmingCharacters(in: .whitespaces) == "---" else {
            throw originalError
        }

        guard let endIndex = lines.dropFirst().firstIndex(where: {
            $0.trimmingCharacters(in: .whitespaces) == "---"
        }) else {
            throw originalError
        }

        let frontmatterLines = lines[1..<endIndex]
        let bodyStart = lines.index(after: endIndex)
        let body = bodyStart < lines.endIndex
            ? lines[bodyStart...].joined(separator: "\n")
            : ""

        let fields = parseSimpleFrontmatterFields(frontmatterLines)
        guard let description = fields["description"], !description.isEmpty else {
            throw originalError
        }

        let metadata = SkillMetadata(
            name: fields["name"] ?? fallbackName,
            description: description,
            license: fields["license"],
            compatibility: fields["compatibility"],
            allowedTools: fields["allowed-tools"]
        )
        return (metadata, body)
    }

    private static func parseSimpleFrontmatterFields(
        _ lines: ArraySlice<String>
    ) -> [String: String] {
        var fields: [String: String] = [:]
        for line in lines {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            guard !trimmed.isEmpty, !trimmed.hasPrefix("#") else {
                continue
            }
            guard let separatorIndex = trimmed.firstIndex(of: ":") else {
                continue
            }

            let key = String(trimmed[..<separatorIndex]).trimmingCharacters(in: .whitespaces)
            let valueStart = trimmed.index(after: separatorIndex)
            let rawValue = String(trimmed[valueStart...]).trimmingCharacters(in: .whitespaces)
            guard !key.isEmpty, !rawValue.isEmpty else {
                continue
            }
            fields[key] = stripMatchingQuotes(rawValue)
        }
        return fields
    }

    private static func stripMatchingQuotes(_ value: String) -> String {
        guard value.count >= 2,
              let first = value.first,
              let last = value.last,
              (first == "\"" && last == "\"") || (first == "'" && last == "'") else {
            return value
        }
        return String(value.dropFirst().dropLast())
    }

    private static func normalizeDirectoryNameIfNeeded(
        _ metadata: SkillMetadata,
        source: SkillSource
    ) -> SkillMetadata {
        guard let expectedDirectoryName = source.expectedDirectoryName,
              metadata.name != expectedDirectoryName,
              SkillMetadata.isValidName(expectedDirectoryName) else {
            return metadata
        }

        return SkillMetadata(
            name: expectedDirectoryName,
            description: metadata.description,
            license: metadata.license,
            compatibility: metadata.compatibility,
            metadata: metadata.metadata,
            allowedTools: metadata.allowedTools
        )
    }

    private static func readSkillFile(at promptFilePath: String) throws -> String {
        do {
            return try String(contentsOfFile: promptFilePath, encoding: .utf8)
        } catch {
            throw SkillError.fileReadError(path: promptFilePath, underlyingError: error)
        }
    }

    private static func resolveSource(at path: String) throws -> SkillSource {
        var isDirectory: ObjCBool = false
        guard FileManager.default.fileExists(atPath: path, isDirectory: &isDirectory) else {
            throw SkillError.skillDirectoryNotFound(path: path)
        }

        if isDirectory.boolValue {
            let promptFilePath = (path as NSString).appendingPathComponent("SKILL.md")
            guard FileManager.default.fileExists(atPath: promptFilePath) else {
                throw SkillError.skillFileNotFound(path: promptFilePath)
            }

            let directoryName = (path as NSString).lastPathComponent
            return SkillSource(
                directoryPath: path,
                promptFilePath: promptFilePath,
                fallbackName: directoryName,
                expectedDirectoryName: directoryName
            )
        }

        guard path.lowercased().hasSuffix(".md") else {
            throw SkillError.skillFileNotFound(path: path)
        }

        let directoryPath = (path as NSString).deletingLastPathComponent
        let fallbackName = ((path as NSString).lastPathComponent as NSString).deletingPathExtension
        return SkillSource(
            directoryPath: directoryPath,
            promptFilePath: path,
            fallbackName: fallbackName,
            expectedDirectoryName: nil
        )
    }
}

private extension SkillMetadata {
    init(skill: SwiftSkill.Skill) {
        self.init(
            name: skill.name,
            description: skill.description,
            license: skill.license,
            compatibility: skill.compatibility,
            metadata: skill.metadata,
            allowedTools: skill.allowedTools?.joined(separator: " ")
        )
    }
}

private struct SkillSource {
    let directoryPath: String
    let promptFilePath: String
    let fallbackName: String
    let expectedDirectoryName: String?
}
