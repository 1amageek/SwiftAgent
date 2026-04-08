//
//  PluginError.swift
//  SwiftAgent
//
//  Created by SwiftAgent on 2026/04/08.
//

import Foundation

/// Errors thrown by the SwiftAgent plugin runtime.
public enum PluginError: Error, LocalizedError, Sendable {
    case notFound(String)
    case invalidManifest(String)
    case manifestValidation([PluginManifestValidationError])
    case commandFailed(String)
    case io(path: String, reason: String)
    case json(String)
    case loadFailures([PluginLoadFailure])

    public var errorDescription: String? {
        switch self {
        case .notFound(let message),
             .invalidManifest(let message),
             .commandFailed(let message),
             .json(let message):
            return message
        case .manifestValidation(let errors):
            return errors.compactMap(\.errorDescription).joined(separator: "\n")
        case .io(let path, let reason):
            return "I/O error at `\(path)`: \(reason)"
        case .loadFailures(let failures):
            return failures.map(\.description).joined(separator: "\n")
        }
    }
}
