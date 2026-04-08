//
//  PluginPermission.swift
//  SwiftAgent
//
//  Created by SwiftAgent on 2026/04/08.
//

import Foundation

/// Manifest-level capabilities granted to a plugin.
public enum PluginPermission: String, Sendable, Codable, Equatable, CaseIterable {
    case read
    case write
    case execute
}
