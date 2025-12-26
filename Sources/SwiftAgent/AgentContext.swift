//
//  AgentContext.swift
//  SwiftAgent
//
//  Created by SwiftAgent on 2025/01/15.
//

import Foundation
import OpenFoundationModels

// MARK: - Agent Context

/// Task-local storage for AgentSession.
///
/// This allows agent sessions to be implicitly passed through the async call tree,
/// similar to SwiftUI's @Environment and SwiftAgent's @Session.
public enum AgentContext {
    @TaskLocal public static var current: AgentSession?
}

// MARK: - Agent Property Wrapper

/// A property wrapper that provides access to the current AgentSession from the task context.
///
/// Usage:
/// ```swift
/// struct MyStep: Step {
///     @Agent var agent: AgentSession
///
///     func run(_ input: String) async throws -> String {
///         // agent is automatically available from context
///         let response = try await agent.prompt(input)
///         return response.content
///     }
/// }
/// ```
@propertyWrapper
public struct Agent: Sendable {
    public init() {}

    public var wrappedValue: AgentSession {
        guard let agent = AgentContext.current else {
            fatalError("No AgentSession available in current context. Use withAgent { } to provide one.")
        }
        return agent
    }
}

// MARK: - Agent Runner

/// Runs an async operation with an AgentSession in context.
///
/// Usage:
/// ```swift
/// let session = try await AgentSession.create(configuration: config)
///
/// let result = try await withAgent(session) {
///     try await myStep.run("Hello")
/// }
/// ```
///
/// - Parameters:
///   - agent: The AgentSession to make available.
///   - operation: The async operation to run with the agent in context.
/// - Returns: The result of the operation.
public func withAgent<T: Sendable>(
    _ agent: AgentSession,
    operation: () async throws -> T
) async rethrows -> T {
    try await AgentContext.$current.withValue(agent, operation: operation)
}

// MARK: - Step Extension for Agent

extension Step {
    /// Runs this step with an AgentSession in context.
    ///
    /// Usage:
    /// ```swift
    /// let result = try await myStep.run("input", agent: agent)
    /// ```
    ///
    /// - Parameters:
    ///   - input: The input to the step.
    ///   - agent: The AgentSession to make available.
    /// - Returns: The output of the step.
    public func run(_ input: Input, agent: AgentSession) async throws -> Output {
        try await withAgent(agent) {
            try await self.run(input)
        }
    }
}

// MARK: - Combined Session and Agent Context

/// Runs an async operation with both LanguageModelSession and AgentSession in context.
///
/// This is useful when you need access to both the low-level session and
/// the high-level agent capabilities.
///
/// - Parameters:
///   - session: The LanguageModelSession.
///   - agent: The AgentSession.
///   - operation: The async operation to run.
/// - Returns: The result of the operation.
public func withSessionAndAgent<T: Sendable>(
    session: LanguageModelSession,
    agent: AgentSession,
    operation: () async throws -> T
) async rethrows -> T {
    try await SessionContext.$current.withValue(session) {
        try await AgentContext.$current.withValue(agent, operation: operation)
    }
}

// MARK: - ToolProvider Context

/// Task-local storage for ToolProvider.
public enum ToolProviderContext {
    @TaskLocal public static var current: ToolProvider?
}

/// A property wrapper that provides access to the current ToolProvider from the task context.
@propertyWrapper
public struct Tools: Sendable {
    public init() {}

    public var wrappedValue: ToolProvider {
        guard let provider = ToolProviderContext.current else {
            return DefaultToolProvider()
        }
        return provider
    }
}

/// Runs an async operation with a ToolProvider in context.
public func withToolProvider<T: Sendable>(
    _ provider: ToolProvider,
    operation: () async throws -> T
) async rethrows -> T {
    try await ToolProviderContext.$current.withValue(provider, operation: operation)
}
