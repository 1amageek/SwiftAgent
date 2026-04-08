//
//  SkillOrigin.swift
//  SwiftAgent
//
//  Created by SwiftAgent on 2026/04/08.
//

import Foundation

/// The on-disk contract used by a discovered skill root.
public enum SkillOrigin: Sendable, Equatable {
    case skillsDirectory
    case legacyCommandsDirectory
}
