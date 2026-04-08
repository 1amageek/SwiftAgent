//
//  PluginHookRunResult.swift
//  SwiftAgent
//
//  Created by SwiftAgent on 2026/04/08.
//

import Foundation
import SwiftAgent

/// Aggregated result returned after running one or more plugin hook commands.
public struct PluginHookRunResult: Sendable, Equatable {
    public let denied: Bool
    public let failed: Bool
    public let messages: [String]
    public let authorizationDecision: ToolAuthorizationDecision?
    public let authorizationReason: String?
    public let updatedInput: String?

    public init(
        denied: Bool = false,
        failed: Bool = false,
        messages: [String] = [],
        authorizationDecision: ToolAuthorizationDecision? = nil,
        authorizationReason: String? = nil,
        updatedInput: String? = nil
    ) {
        self.denied = denied
        self.failed = failed
        self.messages = messages
        self.authorizationDecision = authorizationDecision
        self.authorizationReason = authorizationReason
        self.updatedInput = updatedInput
    }

    public static func allow(messages: [String] = []) -> PluginHookRunResult {
        PluginHookRunResult(messages: messages)
    }
}
