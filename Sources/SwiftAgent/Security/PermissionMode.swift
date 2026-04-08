//
//  PermissionMode.swift
//  SwiftAgent
//
//  Created by SwiftAgent on 2026/04/08.
//

import Foundation

/// Execution mode assigned to a runtime session or required by a plugin tool.
public enum PermissionMode: String, Sendable, Codable, Comparable, CaseIterable {
    case readOnly = "read-only"
    case workspaceWrite = "workspace-write"
    case dangerFullAccess = "danger-full-access"
    case prompt = "prompt"
    case allow = "allow"

    private var rank: Int {
        switch self {
        case .readOnly:
            return 0
        case .workspaceWrite:
            return 1
        case .dangerFullAccess:
            return 2
        case .prompt:
            return 3
        case .allow:
            return 4
        }
    }

    public static func < (lhs: PermissionMode, rhs: PermissionMode) -> Bool {
        lhs.rank < rhs.rank
    }
}
