//
//  SkillLoader.swift
//  SwiftAgent
//
//  Created by SwiftAgent on 2025/01/15.
//

import Foundation

/// Loads and parses SKILL.md files.
///
/// This loader supports the Agent Skills specification format:
///
/// ```markdown
/// ---
/// name: skill-name
/// description: What this skill does
/// license: MIT
/// compatibility: Requires git
/// metadata:
///   author: example-org
///   version: "1.0"
/// allowed-tools: Bash(git:*) Read
/// ---
///
/// # Skill Instructions
///
/// Instructions for the agent...
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

        // Parse frontmatter only
        let (metadata, _) = try parseFrontmatter(content)

        // Validate metadata
        let directoryName = (directoryPath as NSString).lastPathComponent
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

        // Parse frontmatter and body
        let (metadata, body) = try parseFrontmatter(content)

        // Validate metadata
        let directoryName = (directoryPath as NSString).lastPathComponent
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
