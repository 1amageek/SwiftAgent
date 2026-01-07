//
//  ContextableMacro.swift
//  SwiftAgent
//
//  Created by SwiftAgent on 2025/01/07.
//

/// Generates a `ContextKey` and adds `Contextable` conformance.
///
/// This macro:
/// - Generates a `{TypeName}Context` enum conforming to `ContextKey`
/// - Adds `Contextable` conformance to the type
/// - Generates `typealias ContextKeyType`
///
/// The type must define `static var defaultValue` to satisfy the `Contextable` protocol.
///
/// ## Usage
///
/// ```swift
/// @Contextable
/// struct CrawlerConfig {
///     let maxDepth: Int
///     let timeout: Int
///
///     static var defaultValue: CrawlerConfig {
///         CrawlerConfig(maxDepth: 3, timeout: 30)
///     }
/// }
///
/// // Use in a Step
/// struct MyStep: Step {
///     @Context var config: CrawlerConfig
///
///     func run(_ input: URL) async throws -> CrawlResult {
///         print("Max depth: \(config.maxDepth)")
///         // ...
///     }
/// }
///
/// // Provide context via modifier
/// try await MyStep()
///     .context(CrawlerConfig(maxDepth: 10, timeout: 60))
///     .run(startURL)
/// ```
@attached(peer, names: suffixed(Context))
@attached(extension, conformances: Contextable, names: named(ContextKeyType))
public macro Contextable() = #externalMacro(
    module: "SwiftAgentMacros",
    type: "ContextableMacro"
)
