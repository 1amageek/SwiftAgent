//
//  PluginHookEvent.swift
//  SwiftAgent
//
//  Created by SwiftAgent on 2026/04/08.
//

import Foundation

/// Tool lifecycle events supported by `claw-code` compatible plugin hooks.
public enum PluginHookEvent: String, Sendable, Codable, Equatable {
    case preToolUse = "PreToolUse"
    case postToolUse = "PostToolUse"
    case postToolUseFailure = "PostToolUseFailure"
}
