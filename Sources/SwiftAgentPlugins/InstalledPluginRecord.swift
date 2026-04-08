//
//  InstalledPluginRecord.swift
//  SwiftAgent
//
//  Created by SwiftAgent on 2026/04/08.
//

import Foundation

/// Persistent record describing a plugin copied into the install root.
public struct InstalledPluginRecord: Sendable, Codable, Equatable {
    public let kind: PluginKind
    public let id: String
    public let name: String
    public let version: String
    public let description: String
    public let installPath: String
    public let source: PluginInstallSource
    public let installedAtUnixMS: Int64
    public let updatedAtUnixMS: Int64

    public init(
        kind: PluginKind,
        id: String,
        name: String,
        version: String,
        description: String,
        installPath: String,
        source: PluginInstallSource,
        installedAtUnixMS: Int64,
        updatedAtUnixMS: Int64
    ) {
        self.kind = kind
        self.id = id
        self.name = name
        self.version = version
        self.description = description
        self.installPath = installPath
        self.source = source
        self.installedAtUnixMS = installedAtUnixMS
        self.updatedAtUnixMS = updatedAtUnixMS
    }
}

struct InstalledPluginRegistry: Sendable, Codable, Equatable {
    var plugins: [String: InstalledPluginRecord] = [:]
}
