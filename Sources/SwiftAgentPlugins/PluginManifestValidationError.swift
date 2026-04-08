//
//  PluginManifestValidationError.swift
//  SwiftAgent
//
//  Created by SwiftAgent on 2026/04/08.
//

import Foundation

/// A concrete manifest validation failure.
public enum PluginManifestValidationError: Sendable, Equatable {
    case emptyField(field: String)
    case emptyEntryField(kind: String, field: String, name: String?)
    case duplicatePermission(permission: String)
    case invalidPermission(permission: String)
    case duplicateEntry(kind: String, name: String)
    case invalidToolInputSchema(toolName: String)
    case invalidToolRequiredPermission(toolName: String, permission: String)
    case missingPath(kind: String, path: String)
    case pathIsDirectory(kind: String, path: String)
    case unsupportedManifestContract(detail: String)
}

extension PluginManifestValidationError: LocalizedError {
    public var errorDescription: String? {
        switch self {
        case .emptyField(let field):
            return "plugin manifest field `\(field)` cannot be empty"
        case .emptyEntryField(let kind, let field, let name):
            if let name {
                return "\(kind) `\(name)` field `\(field)` cannot be empty"
            }
            return "\(kind) field `\(field)` cannot be empty"
        case .duplicatePermission(let permission):
            return "plugin manifest declares duplicate permission `\(permission)`"
        case .invalidPermission(let permission):
            return "plugin manifest permission `\(permission)` must be read, write, or execute"
        case .duplicateEntry(let kind, let name):
            return "plugin manifest contains duplicate \(kind) `\(name)`"
        case .invalidToolInputSchema(let toolName):
            return "plugin tool `\(toolName)` inputSchema must be a JSON object"
        case .invalidToolRequiredPermission(let toolName, let permission):
            return "plugin tool `\(toolName)` requiredPermission `\(permission)` must be read-only, workspace-write, or danger-full-access"
        case .missingPath(let kind, let path):
            return "\(kind) path `\(path)` does not exist"
        case .pathIsDirectory(let kind, let path):
            return "\(kind) path `\(path)` must point to a file"
        case .unsupportedManifestContract(let detail):
            return detail
        }
    }
}
