//
//  Contextable.swift
//  SwiftAgent
//
//  Created by SwiftAgent on 2025/01/07.
//

// MARK: - Contextable Protocol

/// A protocol that indicates a type can be propagated through nested Steps via TaskLocal.
///
/// Conform to this protocol to share configuration or state across deeply
/// nested Step hierarchies without explicit parameter passing.
///
/// ## Defining a Contextable Type
///
/// Declare the conformance directly. Type-indexed TaskLocal behavior is
/// provided automatically unless the type implements a custom context scope.
///
/// ```swift
/// struct CrawlerConfig: Contextable {
///     let maxDepth: Int
///     let timeout: TimeInterval
///
///     static var defaultValue: CrawlerConfig {
///         CrawlerConfig(maxDepth: 3, timeout: 30)
///     }
/// }
/// ```
///
/// The default type-indexed scope isolates `CrawlerConfig` values from every
/// other context type while preserving TaskLocal inheritance and restoration.
///
/// ## Accessing Context in Steps
///
/// Use ``Context`` property wrapper to access the propagated value:
///
/// ```swift
/// struct FetchStep: Step {
///     @Context var config: CrawlerConfig
///
///     func run(_ url: URL) async throws -> Data {
///         // config.maxDepth and config.timeout are available
///     }
/// }
/// ```
///
/// ## Providing Context
///
/// Use `.context()` modifier to provide context to a Step and all nested children:
///
/// ```swift
/// try await CrawlerPipeline()
///     .context(CrawlerConfig(maxDepth: 10, timeout: 60))
///     .run(startURL)
/// ```
///
/// ## Multiple Contexts
///
/// Chain multiple contexts:
///
/// ```swift
/// try await MyPipeline()
///     .context(DatabaseConfig(...))
///     .context(LoggingConfig(...))
///     .run(input)
/// ```
///
/// ## Reference Types for Mutable State
///
/// Use an actor when you need mutable shared state:
///
/// ```swift
/// actor WorkspaceContext: Contextable {
///     nonisolated let workingDirectory: String
///     private var processedFiles: Set<String> = []
///
///     static var defaultValue: WorkspaceContext {
///         WorkspaceContext(workingDirectory: ".")
///     }
/// }
/// ```
public protocol Contextable: Sendable {
    /// The default value used when no context is explicitly provided.
    static var defaultValue: Self { get }

    /// The value in the current task scope, or ``defaultValue`` when absent.
    static var current: Self { get }

    /// Runs an operation with this value installed in the current task scope.
    static func withValue<Result: Sendable>(
        _ value: Self,
        operation: nonisolated(nonsending) () async throws -> Result
    ) async rethrows -> Result
}

extension Contextable {
    public static var current: Self {
        ContextValueKey<Self>.current
    }

    public static func withValue<Result: Sendable>(
        _ value: Self,
        operation: nonisolated(nonsending) () async throws -> Result
    ) async rethrows -> Result {
        try await ContextValueKey<Self>.withValue(value, operation: operation)
    }
}
