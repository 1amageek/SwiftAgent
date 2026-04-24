//
//  ToolPipeline+SwiftAgentPlugins.swift
//  SwiftAgentPlugins
//

import Foundation
import SwiftAgent

@available(*, deprecated, message: "Use ToolRuntimeConfiguration.withPluginRegistry(_:) instead.")
public extension ToolPipeline {
    func withPluginRegistry(_ pluginRegistry: PluginRegistry) throws -> ToolPipeline {
        let hooks = try pluginRegistry.aggregatedHooks()
        guard !hooks.isEmpty else {
            return self
        }

        let hookMiddleware = PluginHookMiddleware(hookRunner: PluginHookRunner(hooks: hooks))
        let pipeline = ToolPipeline()
        var inserted = false

        for middleware in middlewareList {
            if !inserted, middleware is PermissionMiddleware {
                pipeline.use(hookMiddleware)
                inserted = true
            }
            pipeline.use(middleware)
        }

        if !inserted {
            pipeline.use(hookMiddleware)
        }

        return pipeline
    }
}
