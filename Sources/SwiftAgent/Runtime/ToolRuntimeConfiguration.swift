//
//  ToolRuntimeConfiguration.swift
//  SwiftAgent
//
//  Created by SwiftAgent on 2026/04/23.
//

import Foundation

/// Builder-style configuration for `ToolRuntime`.
///
/// `ToolRuntimeConfiguration` is a value type that collects the tools and
/// middleware needed to assemble a runtime. It mirrors the URLSession
/// pattern: the configuration is a mutable value at setup time, and the
/// runtime created from it is immutable for the duration of its use.
///
/// ## Example
///
/// ```swift
/// var config = ToolRuntimeConfiguration.default
/// config.register(ReadTool())
/// config.register(WriteTool())
/// let runtime = ToolRuntime(configuration: config)
/// ```
///
/// ## Presets
///
/// - ``default`` — installs the standard middleware (event emitting,
///   permissive permissions, no sandbox). This enables `.guardrail { }` to
///   work without explicit security setup.
/// - ``empty`` — no middleware installed. Use when you want total control.
public struct ToolRuntimeConfiguration: Sendable {

    /// The ordered list of middleware. Earlier entries run first.
    public private(set) var middleware: [any ToolMiddleware]

    /// Tools that the LLM sees directly (returned by `publicTools()`).
    public private(set) var publicTools: [any Tool]

    /// Tools that are only invocable by name through the runtime. Useful
    /// for targets of Gateway tools (e.g. a tool that `ToolSearchTool`
    /// resolves at runtime but which the LLM never sees up front).
    public private(set) var hiddenTools: [any Tool]

    // MARK: - Init

    public init(
        middleware: [any ToolMiddleware] = [],
        publicTools: [any Tool] = [],
        hiddenTools: [any Tool] = []
    ) {
        self.middleware = middleware
        self.publicTools = publicTools
        self.hiddenTools = hiddenTools
    }

    // MARK: - Presets

    /// A configuration with the standard middleware stack installed.
    ///
    /// - `EventEmittingMiddleware` — emits `RunEvent` values for observability.
    /// - `PermissionMiddleware` — permissive by default, reads `GuardrailContext`.
    /// - `SandboxMiddleware` — disabled by default, reads `GuardrailContext`.
    ///
    /// This preset enables `.guardrail { }` to affect tool execution without
    /// an explicit `withSecurity()` call.
    public static var `default`: ToolRuntimeConfiguration {
        ToolRuntimeConfiguration(middleware: [
            EventEmittingMiddleware(),
            PermissionMiddleware(configuration: .permissive),
            SandboxMiddleware(configuration: .none),
        ])
    }

    /// A configuration with no middleware. Use when you want to disable
    /// all runtime-level checks.
    public static var empty: ToolRuntimeConfiguration {
        ToolRuntimeConfiguration()
    }

    // MARK: - Mutating Builders

    /// Appends a middleware to the chain.
    @discardableResult
    public mutating func use(_ middleware: any ToolMiddleware) -> Self {
        self.middleware.append(middleware)
        return self
    }

    /// Appends multiple middleware to the chain.
    @discardableResult
    public mutating func use(_ middleware: [any ToolMiddleware]) -> Self {
        self.middleware.append(contentsOf: middleware)
        return self
    }

    /// Inserts a middleware at the given index.
    @discardableResult
    public mutating func insert(_ middleware: any ToolMiddleware, at index: Int) -> Self {
        self.middleware.insert(middleware, at: index)
        return self
    }

    /// Registers a tool.
    ///
    /// - Parameters:
    ///   - tool: The tool to register.
    ///   - isPublic: If `true` (default), the tool is visible to the LLM via
    ///     `ToolRuntime.publicTools()`. If `false`, the tool is only
    ///     invocable by name through `execute(toolName:argumentsJSON:)`.
    ///
    /// - Precondition: `tool.name` must not already be registered in this
    ///   configuration, regardless of visibility. Duplicate names are a
    ///   programmer error and trigger a precondition failure.
    @discardableResult
    public mutating func register(_ tool: any Tool, public isPublic: Bool = true) -> Self {
        if isPublic, let search = tool as? ToolSearchTool {
            registerSingle(search, public: true)
            for inner in search.innerTools {
                registerSingle(inner, public: false)
            }
            return self
        }

        registerSingle(tool, public: isPublic)
        return self
    }

    private mutating func registerSingle(_ tool: any Tool, public isPublic: Bool) {
        let name = tool.name
        precondition(
            !publicTools.contains(where: { $0.name == name }),
            "Tool '\(name)' is already registered as a public tool. Each tool name must be unique within a ToolRuntimeConfiguration."
        )
        precondition(
            !hiddenTools.contains(where: { $0.name == name }),
            "Tool '\(name)' is already registered as a hidden tool. Each tool name must be unique within a ToolRuntimeConfiguration."
        )
        if isPublic {
            publicTools.append(tool)
        } else {
            hiddenTools.append(tool)
        }
    }

    /// Registers multiple tools as public tools.
    ///
    /// - Precondition: Every `tool.name` must be unique both against already
    ///   registered tools and within the provided array.
    @discardableResult
    public mutating func register(_ tools: [any Tool]) -> Self {
        for tool in tools {
            _ = register(tool, public: true)
        }
        return self
    }

    /// Returns a new configuration with dynamic permission rules injected
    /// into the existing `PermissionMiddleware`.
    ///
    /// If no `PermissionMiddleware` is present, the configuration is
    /// returned unchanged.
    public func withDynamicPermissions(
        _ provider: @escaping DynamicPermissionRulesProvider
    ) -> ToolRuntimeConfiguration {
        var copy = self
        copy.middleware = self.middleware.map { mw in
            if let permission = mw as? PermissionMiddleware {
                return PermissionMiddleware(
                    configuration: permission.configuration,
                    dynamicRulesProvider: provider
                )
            }
            return mw
        }
        return copy
    }
}
