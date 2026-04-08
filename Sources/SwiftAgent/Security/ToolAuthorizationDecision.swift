//
//  ToolAuthorizationDecision.swift
//  SwiftAgent
//

import Foundation

/// A generic authorization directive injected by higher-level runtimes.
public enum ToolAuthorizationDecision: String, Sendable, Codable, Equatable {
    case allow
    case deny
    case ask
}
