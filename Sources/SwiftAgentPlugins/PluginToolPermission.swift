//
//  PluginToolPermission.swift
//  SwiftAgent
//
//  Created by SwiftAgent on 2026/04/08.
//

import Foundation
import SwiftAgent

/// Required execution scope for a plugin-defined tool.
public enum PluginToolPermission: String, Sendable, Codable, Equatable, CaseIterable {
    case readOnly = "read-only"
    case workspaceWrite = "workspace-write"
    case dangerFullAccess = "danger-full-access"
}

extension PluginToolPermission {
    var permissionMode: PermissionMode {
        switch self {
        case .readOnly:
            return .readOnly
        case .workspaceWrite:
            return .workspaceWrite
        case .dangerFullAccess:
            return .dangerFullAccess
        }
    }
}
