//
//  PluginToolDefinition.swift
//  SwiftAgent
//
//  Created by SwiftAgent on 2026/04/08.
//

import Foundation

/// A model-facing tool definition contributed by a plugin.
public struct PluginToolDefinition: Sendable, Codable, Equatable {
    public let name: String
    public let description: String?
    public let inputSchema: PluginJSONValue

    public init(
        name: String,
        description: String?,
        inputSchema: PluginJSONValue
    ) {
        self.name = name
        self.description = description
        self.inputSchema = inputSchema
    }
}
