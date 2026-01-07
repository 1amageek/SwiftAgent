//
//  ContextableMacro.swift
//  SwiftAgent
//
//  Created by SwiftAgent on 2025/01/07.
//

/// Generates a `ContextKey` and `ContextKeyType` typealias for a `Contextable` type.
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
/// // Provide context via modifier
/// try await MyStep()
///     .context(config)
///     .run(startURL)
/// ```
@attached(peer, names: suffixed(Context))
@attached(extension, names: named(ContextKeyType))
public macro Contextable() = #externalMacro(
    module: "SwiftAgentMacros",
    type: "ContextableMacro"
)
