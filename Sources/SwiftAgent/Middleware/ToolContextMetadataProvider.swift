//
//  ToolContextMetadataProvider.swift
//  SwiftAgent
//
//  Created by SwiftAgent on 2026/04/08.
//

import Foundation

/// Supplies extra `ToolContext.metadata` entries for a wrapped tool.
public protocol ToolContextMetadataProvider: Sendable {
    func toolContextMetadata(argumentsJSON: String) -> [String: String]
}
