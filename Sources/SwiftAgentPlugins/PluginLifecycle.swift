//
//  PluginLifecycle.swift
//  SwiftAgent
//
//  Created by SwiftAgent on 2026/04/08.
//

import Foundation

/// Initialization and shutdown commands owned by a plugin.
public struct PluginLifecycle: Sendable, Codable, Equatable {
    public let initialize: [String]
    public let shutdown: [String]

    public init(
        initialize: [String] = [],
        shutdown: [String] = []
    ) {
        self.initialize = initialize
        self.shutdown = shutdown
    }

    public var isEmpty: Bool {
        initialize.isEmpty && shutdown.isEmpty
    }

    private enum CodingKeys: String, CodingKey {
        case initialize = "Init"
        case shutdown = "Shutdown"
    }
}
