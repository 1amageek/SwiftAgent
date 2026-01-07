//
//  Contextable.swift
//  SwiftAgent
//
//  Created by SwiftAgent on 2025/01/07.
//

import Foundation

// MARK: - Contextable Protocol

/// A protocol that indicates a type can be propagated as a Context.
///
/// Conform to this protocol to enable automatic `ContextKey` generation
/// via the `@Contextable` macro.
///
/// ## Usage
///
/// ```swift
/// @Contextable
/// struct CrawlerConfig: Contextable {
///     static var defaultValue: CrawlerConfig {
///         CrawlerConfig(maxDepth: 3, timeout: 30)
///     }
///
///     let maxDepth: Int
///     let timeout: Int
/// }
///
/// // The macro generates CrawlerConfigContext: ContextKey
/// // and extension CrawlerConfig { typealias ContextKeyType = CrawlerConfigContext }
///
/// // Use in a Step
/// struct MyStep: Step {
///     @Context var config
///
///     func run(_ input: URL) async throws -> CrawlResult {
///         print("Max depth: \(config.maxDepth)")
///         // ...
///     }
/// }
///
/// // Provide the context via modifier
/// try await MyStep()
///     .context(config)
///     .run(startURL)
/// ```
public protocol Contextable: Sendable {
    /// The associated ContextKey type.
    associatedtype ContextKeyType: ContextKey where ContextKeyType.Value == Self

    /// The default value when no context is provided.
    static var defaultValue: Self { get }
}
