//
//  PluginManagerConfig.swift
//  SwiftAgent
//
//  Created by SwiftAgent on 2026/04/08.
//

import Foundation

/// Input roots used to build a runtime plugin registry.
public struct PluginManagerConfig: Sendable, Equatable {
    public let configHome: String
    public var enabledPlugins: [String: Bool]
    public let builtinRoots: [String]
    public let bundledRoots: [String]
    public let externalRoots: [String]
    public let installRoot: String?
    public let registryPath: String?

    public init(
        configHome: String = PluginManagerConfig.defaultConfigHome(),
        enabledPlugins: [String: Bool] = [:],
        builtinRoots: [String] = [],
        bundledRoots: [String] = [],
        externalRoots: [String] = [],
        installRoot: String? = nil,
        registryPath: String? = nil
    ) {
        self.configHome = configHome
        self.enabledPlugins = enabledPlugins
        self.builtinRoots = builtinRoots
        self.bundledRoots = bundledRoots
        self.externalRoots = externalRoots
        self.installRoot = installRoot
        self.registryPath = registryPath
    }

    public static func defaultConfigHome() -> String {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".swiftagent")
            .path
    }
}
