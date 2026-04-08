//
//  PluginHooks.swift
//  SwiftAgent
//
//  Created by SwiftAgent on 2026/04/08.
//

import Foundation

/// Tool lifecycle hooks contributed by one or more plugins.
public struct PluginHooks: Sendable, Codable, Equatable {
    public let preToolUse: [String]
    public let postToolUse: [String]
    public let postToolUseFailure: [String]

    public init(
        preToolUse: [String] = [],
        postToolUse: [String] = [],
        postToolUseFailure: [String] = []
    ) {
        self.preToolUse = preToolUse
        self.postToolUse = postToolUse
        self.postToolUseFailure = postToolUseFailure
    }

    public var isEmpty: Bool {
        preToolUse.isEmpty && postToolUse.isEmpty && postToolUseFailure.isEmpty
    }

    public func merged(with other: PluginHooks) -> PluginHooks {
        PluginHooks(
            preToolUse: preToolUse + other.preToolUse,
            postToolUse: postToolUse + other.postToolUse,
            postToolUseFailure: postToolUseFailure + other.postToolUseFailure
        )
    }

    private enum CodingKeys: String, CodingKey {
        case preToolUse = "PreToolUse"
        case postToolUse = "PostToolUse"
        case postToolUseFailure = "PostToolUseFailure"
    }
}
