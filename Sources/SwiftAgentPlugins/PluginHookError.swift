//
//  PluginHookError.swift
//  SwiftAgent
//
//  Created by SwiftAgent on 2026/04/08.
//

import Foundation

/// Error emitted when a plugin hook blocks or fails a tool invocation.
public enum PluginHookError: Error, LocalizedError, Sendable, Equatable {
    case denied(messages: [String])
    case failed(messages: [String])

    public var errorDescription: String? {
        switch self {
        case .denied(let messages):
            return messages.isEmpty ? "Plugin hook denied the tool invocation." : messages.joined(separator: "\n")
        case .failed(let messages):
            return messages.isEmpty ? "Plugin hook failed while handling the tool invocation." : messages.joined(separator: "\n")
        }
    }
}
