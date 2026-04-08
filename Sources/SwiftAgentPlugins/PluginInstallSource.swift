//
//  PluginInstallSource.swift
//  SwiftAgent
//
//  Created by SwiftAgent on 2026/04/08.
//

import Foundation

/// Source persisted for an installed plugin so it can be updated later.
public enum PluginInstallSource: Sendable, Codable, Equatable {
    case localPath(path: String)
    case gitURL(url: String)

    public var description: String {
        switch self {
        case .localPath(let path):
            return path
        case .gitURL(let url):
            return url
        }
    }
}
