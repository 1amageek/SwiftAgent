//
//  Session.swift
//  SwiftAgent
//
//  Created by SwiftAgent on 2025/01/31.
//

import Foundation

// MARK: - Session Context

/// Task-local storage for LanguageModelSession
///
/// This allows session to be implicitly passed through the async call tree,
/// similar to SwiftUI's @Environment.
public enum SessionContext {
    @TaskLocal public static var current: LanguageModelSession?
}

// MARK: - Session Property Wrapper

/// A property wrapper that provides access to the current LanguageModelSession from the task context.
///
/// Usage:
/// ```swift
/// struct MyStep: Step {
///     @Session var session: LanguageModelSession
///
///     func run(_ input: String) async throws -> String {
///         // session is automatically available from context
///         let response = try await session.respond { Prompt(input) }
///         return response.content
///     }
/// }
/// ```
@propertyWrapper
public struct Session: Sendable {
    public init() {}

    public var wrappedValue: LanguageModelSession {
        guard let session = SessionContext.current else {
            fatalError("No LanguageModelSession available in current context. Use withSession { } to provide one.")
        }
        return session
    }
}

// MARK: - Session Runner

/// Runs an async operation with a LanguageModelSession in context.
///
/// Usage:
/// ```swift
/// let session = LanguageModelSession(model: myModel) {
///     Instructions("You are a helpful assistant")
/// }
///
/// let result = try await withSession(session) {
///     try await myStep.run("Hello")
/// }
/// ```
///
/// - Parameters:
///   - session: The LanguageModelSession to make available
///   - operation: The async operation to run with the session in context
/// - Returns: The result of the operation
public func withSession<T: Sendable>(
    _ session: LanguageModelSession,
    operation: () async throws -> T
) async rethrows -> T {
    try await SessionContext.$current.withValue(session, operation: operation)
}

// MARK: - Step Extension for Session

extension Step {
    /// Runs this step with a LanguageModelSession in context.
    ///
    /// Usage:
    /// ```swift
    /// let result = try await myStep.run("input", session: session)
    /// ```
    ///
    /// - Parameters:
    ///   - input: The input to the step
    ///   - session: The LanguageModelSession to make available
    /// - Returns: The output of the step
    public func run(_ input: Input, session: LanguageModelSession) async throws -> Output {
        try await withSession(session) {
            try await self.run(input)
        }
    }
}
