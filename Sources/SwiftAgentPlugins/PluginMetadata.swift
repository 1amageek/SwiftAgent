//
//  PluginMetadata.swift
//  SwiftAgent
//
//  Created by SwiftAgent on 2026/04/08.
//

import Foundation

/// Summary metadata for a loaded plugin.
public struct PluginMetadata: Sendable, Codable, Equatable {
    public let id: String
    public let name: String
    public let version: String
    public let description: String
    public let kind: PluginKind
    public let source: String
    public let defaultEnabled: Bool
    public let rootPath: String?

    public init(
        id: String,
        name: String,
        version: String,
        description: String,
        kind: PluginKind,
        source: String,
        defaultEnabled: Bool,
        rootPath: String?
    ) {
        self.id = id
        self.name = name
        self.version = version
        self.description = description
        self.kind = kind
        self.source = source
        self.defaultEnabled = defaultEnabled
        self.rootPath = rootPath
    }
}
