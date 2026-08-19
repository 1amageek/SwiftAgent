//
//  AgentConfiguration.swift
//  AgentCLI
//
//  Created by SwiftAgent on 2025/01/17.
//

import Foundation
import AgentTools
import SwiftAgent

/// Configuration for agent setup
public struct AgentConfiguration: Sendable {

    /// API key supplied by the CLI. The current sample uses the platform model
    /// through SwiftAgent; provider-backed wiring belongs in a dedicated backend.
    public let apiKey: String

    /// Model to use
    public let model: String

    /// Enable verbose logging
    public let verbose: Bool

    /// Working directory for file operations
    public let workingDirectory: String

    /// Explicitly policy-enforced web access. A nil value keeps networking disabled.
    public let webDocumentFetcher: (any WebDocumentFetching)?

    public init(
        apiKey: String,
        model: String = "gpt-4.1",
        verbose: Bool = false,
        workingDirectory: String = FileManager.default.currentDirectoryPath,
        webDocumentFetcher: (any WebDocumentFetching)? = nil
    ) {
        self.apiKey = apiKey
        self.model = model
        self.verbose = verbose
        self.workingDirectory = workingDirectory
        self.webDocumentFetcher = webDocumentFetcher
    }

    /// Creates a LanguageModelSession with the specified tools and instructions
    public func createSession(
        tools: [any Tool] = [],
        instructions: Instructions
    ) -> LanguageModelSession {
        LanguageModelSession(tools: tools) {
            instructions
        }
    }
}
