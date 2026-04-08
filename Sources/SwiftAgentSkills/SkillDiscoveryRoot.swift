//
//  SkillDiscoveryRoot.swift
//  SwiftAgent
//
//  Created by SwiftAgent on 2026/04/08.
//

import Foundation

/// A concrete root searched during skill discovery.
public struct SkillDiscoveryRoot: Sendable, Equatable {
    public let path: String
    public let origin: SkillOrigin

    public init(path: String, origin: SkillOrigin) {
        self.path = path
        self.origin = origin
    }
}
