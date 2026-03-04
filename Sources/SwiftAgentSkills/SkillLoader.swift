//
//  SkillLoader.swift
//  SwiftAgent
//
//  Created by SwiftAgent on 2025/01/15.
//

import Foundation

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

    /// Loads only metadata from a SKILL.md file (discovery phase).
    ///
    /// This is efficient for startup when we only need name and description
    /// to build the `<available_skills>` prompt.
    ///
    /// - Parameter directoryPath: Path to the skill directory.
    /// - Returns: Skill with metadata only (instructions = nil).
    /// - Throws: `SkillError` if loading fails.
    public static func loadMetadata(from directoryPath: String) throws -> Skill {
        let skillFilePath = (directoryPath as NSString).appendingPathComponent("SKILL.md")

        // Check directory exists
        var isDirectory: ObjCBool = false
        guard FileManager.default.fileExists(atPath: directoryPath, isDirectory: &isDirectory),
              isDirectory.boolValue else {
            throw SkillError.skillDirectoryNotFound(path: directoryPath)
        }

        // Check SKILL.md exists
        guard FileManager.default.fileExists(atPath: skillFilePath) else {
            throw SkillError.skillFileNotFound(path: skillFilePath)
        }

        // Read file content
        let content: String
        do {
            content = try String(contentsOfFile: skillFilePath, encoding: .utf8)
        } catch {
            throw SkillError.fileReadError(path: skillFilePath, underlyingError: error)
        }

        // Detect format and parse
        let directoryName = (directoryPath as NSString).lastPathComponent
        let metadata: SkillMetadata
        if hasFrontmatter(content) {
            (metadata, _) = try parseFrontmatter(content)
        } else {
            (metadata, _) = try parseMarkdownSkill(content, directoryName: directoryName)
        }

        // Validate metadata
        try metadata.validate(directoryName: directoryName)

        return Skill(
            metadata: metadata,
            instructions: nil,
            directoryPath: directoryPath
        )
    }

    /// Loads full skill including instructions (activation phase).
    ///
    /// - Parameter directoryPath: Path to the skill directory.
    /// - Returns: Skill with full instructions.
    /// - Throws: `SkillError` if loading fails.
    public static func loadFull(from directoryPath: String) throws -> Skill {
        let skillFilePath = (directoryPath as NSString).appendingPathComponent("SKILL.md")

        // Check directory exists
        var isDirectory: ObjCBool = false
        guard FileManager.default.fileExists(atPath: directoryPath, isDirectory: &isDirectory),
              isDirectory.boolValue else {
            throw SkillError.skillDirectoryNotFound(path: directoryPath)
        }

        // Check SKILL.md exists
        guard FileManager.default.fileExists(atPath: skillFilePath) else {
            throw SkillError.skillFileNotFound(path: skillFilePath)
        }

        // Read file content
        let content: String
        do {
            content = try String(contentsOfFile: skillFilePath, encoding: .utf8)
        } catch {
            throw SkillError.fileReadError(path: skillFilePath, underlyingError: error)
        }

        // Detect format and parse
        let directoryName = (directoryPath as NSString).lastPathComponent
        let metadata: SkillMetadata
        let body: String
        if hasFrontmatter(content) {
            (metadata, body) = try parseFrontmatter(content)
        } else {
            (metadata, body) = try parseMarkdownSkill(content, directoryName: directoryName)
        }

        // Validate metadata
        try metadata.validate(directoryName: directoryName)

        return Skill(
            metadata: metadata,
            instructions: body.trimmingCharacters(in: .whitespacesAndNewlines),
            directoryPath: directoryPath
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
        return try loadFull(from: skill.directoryPath)
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
    ///   - directoryName: Parent directory name used as the skill name.
    /// - Returns: Tuple of (metadata, body).
    /// - Throws: `SkillError.invalidFormat` if content is empty.
    static func parseMarkdownSkill(
        _ content: String,
        directoryName: String
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
            ? directoryName
            : descriptionLines.joined(separator: " ")

        let metadata = SkillMetadata(
            name: directoryName,
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
        let lines = content.components(separatedBy: .newlines)

        // Find frontmatter delimiters
        guard let firstLine = lines.first, firstLine.trimmingCharacters(in: .whitespaces) == "---" else {
            throw SkillError.invalidFormat(reason: "SKILL.md must start with '---'")
        }

        // Find closing delimiter
        var endIndex: Int?
        for (index, line) in lines.enumerated() where index > 0 {
            if line.trimmingCharacters(in: .whitespaces) == "---" {
                endIndex = index
                break
            }
        }

        guard let closingIndex = endIndex else {
            throw SkillError.invalidFormat(reason: "Missing closing '---' for frontmatter")
        }

        // Extract frontmatter lines
        let frontmatterLines = Array(lines[1..<closingIndex])

        // Extract body
        let bodyLines = Array(lines[(closingIndex + 1)...])
        let body = bodyLines.joined(separator: "\n")

        // Parse frontmatter
        let metadata = try parseYAMLFrontmatter(frontmatterLines)

        return (metadata, body)
    }

    // MARK: - Simple YAML Parser

    /// Parses simple YAML frontmatter.
    ///
    /// Supports:
    /// - Simple key: value pairs
    /// - Nested metadata block (one level deep)
    /// - String values (with or without quotes)
    ///
    /// - Parameter lines: Lines of YAML content (without delimiters).
    /// - Returns: Parsed SkillMetadata.
    /// - Throws: `SkillError.frontmatterParsingError` if parsing fails.
    private static func parseYAMLFrontmatter(_ lines: [String]) throws -> SkillMetadata {
        var values: [String: String] = [:]
        var metadataDict: [String: String] = [:]
        var inMetadataBlock = false

        for line in lines {
            // Skip empty lines
            if line.trimmingCharacters(in: .whitespaces).isEmpty {
                continue
            }

            // Check if this is an indented line (part of metadata block)
            let trimmedLine = line.trimmingCharacters(in: .whitespaces)
            let leadingSpaces = line.prefix(while: { $0 == " " || $0 == "\t" }).count

            if inMetadataBlock && leadingSpaces > 0 {
                // Parse nested key-value pair
                if let (key, value) = parseKeyValue(trimmedLine) {
                    metadataDict[key] = value
                }
                continue
            }

            // Check if we're entering the metadata block
            if trimmedLine == "metadata:" {
                inMetadataBlock = true
                continue
            }

            // Regular key-value pair
            inMetadataBlock = false
            if let (key, value) = parseKeyValue(trimmedLine) {
                values[key] = value
            }
        }

        // Validate required fields
        guard let name = values["name"], !name.isEmpty else {
            throw SkillError.frontmatterParsingError(reason: "Missing required field 'name'")
        }

        guard let description = values["description"], !description.isEmpty else {
            throw SkillError.frontmatterParsingError(reason: "Missing required field 'description'")
        }

        return SkillMetadata(
            name: name,
            description: description,
            license: values["license"],
            compatibility: values["compatibility"],
            metadata: metadataDict.isEmpty ? nil : metadataDict,
            allowedTools: values["allowed-tools"]
        )
    }

    /// Parses a single key: value line.
    ///
    /// - Parameter line: A single YAML line.
    /// - Returns: Tuple of (key, value) or nil if invalid.
    private static func parseKeyValue(_ line: String) -> (String, String)? {
        guard let colonIndex = line.firstIndex(of: ":") else {
            return nil
        }

        let key = String(line[..<colonIndex]).trimmingCharacters(in: .whitespaces)
        var value = String(line[line.index(after: colonIndex)...]).trimmingCharacters(in: .whitespaces)

        // Remove surrounding quotes if present
        if (value.hasPrefix("\"") && value.hasSuffix("\"")) ||
           (value.hasPrefix("'") && value.hasSuffix("'")) {
            value = String(value.dropFirst().dropLast())
        }

        guard !key.isEmpty else {
            return nil
        }

        return (key, value)
    }
}
