//
//  PluginUpdateOutcome.swift
//  SwiftAgent
//
//  Created by SwiftAgent on 2026/04/08.
//

import Foundation

/// Result returned when an installed plugin is refreshed from its original source.
public struct PluginUpdateOutcome: Sendable, Equatable {
    public let pluginID: String
    public let oldVersion: String
    public let newVersion: String
    public let installPath: String

    public init(
        pluginID: String,
        oldVersion: String,
        newVersion: String,
        installPath: String
    ) {
        self.pluginID = pluginID
        self.oldVersion = oldVersion
        self.newVersion = newVersion
        self.installPath = installPath
    }
}
