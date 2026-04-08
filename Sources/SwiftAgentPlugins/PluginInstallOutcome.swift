//
//  PluginInstallOutcome.swift
//  SwiftAgent
//
//  Created by SwiftAgent on 2026/04/08.
//

import Foundation

/// Result returned when a plugin source is installed into the local registry.
public struct PluginInstallOutcome: Sendable, Equatable {
    public let pluginID: String
    public let version: String
    public let installPath: String

    public init(pluginID: String, version: String, installPath: String) {
        self.pluginID = pluginID
        self.version = version
        self.installPath = installPath
    }
}
