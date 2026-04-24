//
//  ToolRuntimeConfiguration+SwiftAgentPlugins.swift
//  SwiftAgentPlugins
//

import Foundation
import SwiftAgent

public extension ToolRuntimeConfiguration {
    /// Returns a configuration with a `PluginHookMiddleware` inserted before
    /// the existing `PermissionMiddleware`, using hooks aggregated from the
    /// given plugin registry.
    ///
    /// If the registry produces no hooks, the configuration is returned
    /// unchanged. If no `PermissionMiddleware` is present, the hook
    /// middleware is appended at the end.
    func withPluginRegistry(_ pluginRegistry: PluginRegistry) throws -> ToolRuntimeConfiguration {
        let hooks = try pluginRegistry.aggregatedHooks()
        guard !hooks.isEmpty else {
            return self
        }

        let hookMiddleware = PluginHookMiddleware(hookRunner: PluginHookRunner(hooks: hooks))
        var rebuilt = ToolRuntimeConfiguration(publicTools: publicTools, hiddenTools: hiddenTools)
        var inserted = false

        for middleware in middleware {
            if !inserted, middleware is PermissionMiddleware {
                rebuilt.use(hookMiddleware)
                inserted = true
            }
            rebuilt.use(middleware)
        }

        if !inserted {
            rebuilt.use(hookMiddleware)
        }

        return rebuilt
    }
}
