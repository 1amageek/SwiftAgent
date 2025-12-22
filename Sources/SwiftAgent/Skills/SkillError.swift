//
//  SkillError.swift
//  SwiftAgent
//
//  Created by SwiftAgent on 2025/01/15.
//

import Foundation

/// Errors that can occur during skill operations.
public enum SkillError: Error, LocalizedError, Sendable {

    /// Skill directory not found.
    case skillDirectoryNotFound(path: String)

    /// SKILL.md file not found.
    case skillFileNotFound(path: String)

    /// Invalid SKILL.md format.
    case invalidFormat(reason: String)

    /// Validation failed.
    case validationFailed(field: String, reason: String)

    /// Skill not found in registry.
    case skillNotFound(name: String)

    /// Skill already exists.
    case skillAlreadyExists(name: String)

    /// Failed to read file.
    case fileReadError(path: String, underlyingError: Error)

    /// Frontmatter parsing error.
    case frontmatterParsingError(reason: String)

    public var errorDescription: String? {
        switch self {
        case .skillDirectoryNotFound(let path):
            return "Skill directory not found: \(path)"
        case .skillFileNotFound(let path):
            return "SKILL.md not found: \(path)"
        case .invalidFormat(let reason):
            return "Invalid SKILL.md format: \(reason)"
        case .validationFailed(let field, let reason):
            return "Validation failed for '\(field)': \(reason)"
        case .skillNotFound(let name):
            return "Skill not found: \(name)"
        case .skillAlreadyExists(let name):
            return "Skill already exists: \(name)"
        case .fileReadError(let path, let error):
            return "Failed to read file '\(path)': \(error.localizedDescription)"
        case .frontmatterParsingError(let reason):
            return "Frontmatter parsing error: \(reason)"
        }
    }
}
