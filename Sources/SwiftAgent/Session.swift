//
//  Session.swift
//  SwiftAgent
//
//  Created by SwiftAgent on 2025/01/18.
//

import Foundation
import OpenFoundationModels

/// A property wrapper for managing LanguageModelSession instances with memory storage.
///
/// `Session` provides a convenient way to create and share LanguageModelSession instances
/// across multiple Steps, using the Memory pattern for value management.
///
/// Example usage:
/// ```swift
/// struct MyAgent {
///     @Session
///     var session = LanguageModelSession(
///         instructions: Instructions("You are a helpful assistant")
///     )
///
///     // Or using InstructionsBuilder
///     @Session {
///         "You are an expert"
///         "Be concise"
///     }
///     var expertSession
/// }
/// ```
@propertyWrapper
public struct Session: Sendable {
    private let storage: Memory<LanguageModelSession>
    
    /// Initializes a Session with an existing LanguageModelSession
    public init(wrappedValue: LanguageModelSession) {
        self.storage = Memory(wrappedValue: wrappedValue)
    }
    
    /// Initializes a Session with InstructionsBuilder
    /// - Parameter instructions: A closure that builds Instructions using InstructionsBuilder
    public init(@InstructionsBuilder instructions: () -> Instructions) {
        let session = LanguageModelSession(
            model: SystemLanguageModel.default
        ) {
            instructions()
        }
        self.storage = Memory(wrappedValue: session)
    }
    
    /// Initializes a Session with InstructionsBuilder and additional configuration
    /// - Parameters:
    ///   - tools: Tools to be used by the model
    ///   - instructions: A closure that builds Instructions using InstructionsBuilder
    public init(
        tools: [any OpenFoundationModels.Tool] = [],
        @InstructionsBuilder instructions: () -> Instructions
    ) {
        let session = LanguageModelSession(
            model: SystemLanguageModel.default,
            tools: tools
        ) {
            instructions()
        }
        self.storage = Memory(wrappedValue: session)
    }
    
    /// The wrapped LanguageModelSession value
    public var wrappedValue: LanguageModelSession {
        get { storage.wrappedValue }
        nonmutating set { storage.wrappedValue = newValue }
    }
    
    /// A Relay projection for sharing the session across Steps
    public var projectedValue: Relay<LanguageModelSession> {
        storage.projectedValue
    }
}