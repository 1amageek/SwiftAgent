//
//  PluginKind.swift
//  SwiftAgent
//
//  Created by SwiftAgent on 2026/04/08.
//

import Foundation

/// The source category for a runtime plugin.
public enum PluginKind: String, Sendable, Codable, Equatable {
    case builtin
    case bundled
    case external

    /// Marketplace label used by `claw-code` compatible plugin IDs.
    public var marketplace: String {
        switch self {
        case .builtin:
            return "builtin"
        case .bundled:
            return "bundled"
        case .external:
            return "external"
        }
    }
}
