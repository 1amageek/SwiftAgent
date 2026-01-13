//
//  Contextable.swift
//  SwiftAgent
//
//  Created by SwiftAgent on 2025/01/07.
//

import Foundation

// MARK: - Contextable Protocol

/// A protocol that indicates a type can be propagated through nested Steps via TaskLocal.
///
/// Conform to this protocol to enable automatic `ContextKey` generation
/// via the `@Contextable` macro. This allows sharing configuration or state
/// across deeply nested Step hierarchies without explicit parameter passing.
///
/// ## Defining a Contextable Type
///
/// Use the `@Contextable` macro to automatically generate the required `ContextKey`:
///
/// ```swift
/// @Contextable
/// struct CrawlerConfig {
///     let maxDepth: Int
///     let timeout: TimeInterval
///
///     static var defaultValue: CrawlerConfig {
///         CrawlerConfig(maxDepth: 3, timeout: 30)
///     }
/// }
/// ```
///
/// The macro generates:
/// - `CrawlerConfigContext` enum conforming to ``ContextKey``
/// - `typealias ContextKeyType = CrawlerConfigContext` on `CrawlerConfig`
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
/// Use classes when you need mutable shared state:
///
/// ```swift
/// @Contextable
/// class WorkspaceContext {
///     let workingDirectory: String
///     var processedFiles: Set<String> = []
///
///     static var defaultValue: WorkspaceContext {
///         WorkspaceContext(workingDirectory: ".")
///     }
/// }
/// ```
public protocol Contextable: Sendable {
    /// The associated ContextKey type that manages TaskLocal storage.
    associatedtype ContextKeyType: ContextKey where ContextKeyType.Value == Self

    /// The default value used when no context is explicitly provided.
    static var defaultValue: Self { get }
}
