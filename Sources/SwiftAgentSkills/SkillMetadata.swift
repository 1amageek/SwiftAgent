//
//  SkillMetadata.swift
//  SwiftAgent
//
//  Created by SwiftAgent on 2025/01/15.
//

import Foundation

/// Metadata from SKILL.md frontmatter.
///
/// This struct represents the YAML frontmatter section of a SKILL.md file.
/// It follows the Agent Skills specification.
///
/// ## Example SKILL.md Frontmatter
///
/// ```yaml
/// ---
/// name: pdf-processing
/// description: Extract text and tables from PDF files.
/// license: Apache-2.0
/// compatibility: Requires poppler
/// metadata:
///   author: example-org
///   version: "1.0"
/// allowed-tools: Bash(pdftotext:*) Read
/// ---
/// ```
public struct SkillMetadata: Sendable, Codable, Equatable {

    // MARK: - Required Fields

    /// Skill name.
    ///
    /// Must be 1-64 characters, lowercase alphanumeric with hyphens only.
    /// Must match the pattern `^[a-z0-9]+(-[a-z0-9]+)*$`.
    /// Must match the parent directory name.
    public let name: String

    /// Description of what the skill does.
    ///
    /// Must be 1-1024 characters. Should describe both what the skill does
    /// and when to use it.
    public let description: String

    // MARK: - Optional Fields

    /// License information.
    public let license: String?

    /// Environment compatibility requirements.
    ///
    /// Maximum 500 characters. Indicates required system packages,
    /// network access, or specific agent products.
    public let compatibility: String?

    /// Custom metadata key-value pairs.
    public let metadata: [String: String]?

    /// Space-delimited list of pre-approved tools.
    ///
    /// Experimental field. Support may vary between agent implementations.
    public let allowedTools: String?

    // MARK: - Initialization

    /// Creates skill metadata.
    ///
    /// - Parameters:
    ///   - name: Skill name (1-64 chars, lowercase alphanumeric + hyphens).
    ///   - description: Description (1-1024 chars).
    ///   - license: Optional license information.
    ///   - compatibility: Optional compatibility requirements.
    ///   - metadata: Optional custom metadata.
    ///   - allowedTools: Optional pre-approved tools list.
    public init(
        name: String,
        description: String,
        license: String? = nil,
        compatibility: String? = nil,
        metadata: [String: String]? = nil,
        allowedTools: String? = nil
    ) {
        self.name = name
        self.description = description
        self.license = license
        self.compatibility = compatibility
        self.metadata = metadata
        self.allowedTools = allowedTools
    }

    // MARK: - Coding Keys

    private enum CodingKeys: String, CodingKey {
        case name
        case description
        case license
        case compatibility
        case metadata
        case allowedTools = "allowed-tools"
    }
}

// MARK: - Validation

extension SkillMetadata {

    /// Regular expression pattern for valid skill names.
    public static let namePattern = "^[a-z0-9]+(-[a-z0-9]+)*$"

    /// Validates the metadata.
    ///
    /// - Parameter directoryName: The skill directory name (must match `name`).
    /// - Throws: `SkillError.validationFailed` if validation fails.
    public func validate(directoryName: String? = nil) throws {
        // Validate name
        guard !name.isEmpty else {
            throw SkillError.validationFailed(field: "name", reason: "cannot be empty")
        }

        guard name.count <= 64 else {
            throw SkillError.validationFailed(field: "name", reason: "must be 64 characters or less")
        }

        let nameRegex = try! NSRegularExpression(pattern: Self.namePattern)
        let nameRange = NSRange(name.startIndex..., in: name)
        guard nameRegex.firstMatch(in: name, range: nameRange) != nil else {
            throw SkillError.validationFailed(
                field: "name",
                reason: "must contain only lowercase letters, numbers, and hyphens; cannot start or end with hyphen"
            )
        }

        // Validate name matches directory
        if let dirName = directoryName, dirName != name {
            throw SkillError.validationFailed(
                field: "name",
                reason: "must match directory name '\(dirName)'"
            )
        }

        // Validate description
        guard !description.isEmpty else {
            throw SkillError.validationFailed(field: "description", reason: "cannot be empty")
        }

        guard description.count <= 1024 else {
            throw SkillError.validationFailed(field: "description", reason: "must be 1024 characters or less")
        }

        // Validate compatibility length
        if let compat = compatibility, compat.count > 500 {
            throw SkillError.validationFailed(field: "compatibility", reason: "must be 500 characters or less")
        }
    }
}

// MARK: - Debug Description

extension SkillMetadata: CustomDebugStringConvertible {

    public var debugDescription: String {
        "SkillMetadata(name: \"\(name)\", description: \"\(self.description.prefix(50))...\")"
    }
}
