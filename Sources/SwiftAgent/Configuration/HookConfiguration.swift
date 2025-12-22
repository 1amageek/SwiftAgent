//
//  HookConfiguration.swift
//  SwiftAgent
//
//  Created by SwiftAgent on 2025/01/23.
//

import Foundation

/// Configuration for hook registration and settings.
///
/// `HookConfiguration` defines which hooks are registered for different events
/// and their matching criteria.
///
/// ## Configuration File Format
///
/// Hooks can be defined in a JSON settings file:
///
/// ```json
/// {
///   "hooks": {
///     "preToolUse": [
///       {
///         "matcher": "Bash",
///         "type": "logging",
///         "priority": 100
///       }
///     ],
///     "postToolUse": [
///       {
///         "matcher": "Edit|Write",
///         "type": "logging",
///         "priority": 0
///       }
///     ]
///   }
/// }
/// ```
public struct HookConfiguration: Codable, Sendable {

    /// Hook definitions by event type.
    public var hooks: [String: [HookDefinition]]

    /// Creates a hook configuration.
    public init(hooks: [String: [HookDefinition]] = [:]) {
        self.hooks = hooks
    }

    /// Applies this configuration to a hook manager.
    public func apply(to manager: HookManager, handlerFactory: HookHandlerFactory) async throws {
        for (eventName, definitions) in hooks {
            guard let event = HookEvent(rawValue: eventName) else {
                throw HookConfigurationError.unknownEvent(eventName)
            }

            for definition in definitions {
                let handler = try handlerFactory.createHandler(for: definition)
                let matcher = definition.matcher.map { ToolMatcher(pattern: $0) }

                await manager.register(
                    handler,
                    for: event,
                    matcher: matcher,
                    priority: definition.priority ?? 0
                )
            }
        }
    }

    /// Gets hook definitions for a specific event.
    public func definitions(for event: HookEvent) -> [HookDefinition] {
        hooks[event.rawValue] ?? []
    }

    /// Adds a hook definition for an event.
    public mutating func addHook(_ definition: HookDefinition, for event: HookEvent) {
        if hooks[event.rawValue] == nil {
            hooks[event.rawValue] = []
        }
        hooks[event.rawValue]?.append(definition)
    }
}

// MARK: - HookDefinition

/// Definition of a single hook from configuration.
public struct HookDefinition: Codable, Sendable {

    /// The type of hook handler.
    public var type: String

    /// Optional matcher pattern for filtering.
    public var matcher: String?

    /// Priority for ordering (higher runs first).
    public var priority: Int?

    /// Additional options for the handler.
    public var options: [String: AnyCodable]?

    /// Creates a hook definition.
    public init(
        type: String,
        matcher: String? = nil,
        priority: Int? = nil,
        options: [String: AnyCodable]? = nil
    ) {
        self.type = type
        self.matcher = matcher
        self.priority = priority
        self.options = options
    }
}

// MARK: - AnyCodable

/// Type-erased Codable value for flexible configuration options.
///
/// Uses a Sendable-compatible internal representation.
public struct AnyCodable: Codable, Sendable {

    /// Sendable value types supported by AnyCodable.
    private enum ValueType: Sendable {
        case null
        case bool(Bool)
        case int(Int)
        case double(Double)
        case string(String)
        case array([AnyCodable])
        case dictionary([String: AnyCodable])
    }

    private let storage: ValueType

    /// The raw value (not Sendable-safe, use with caution).
    public var value: Any {
        switch storage {
        case .null:
            return ()
        case .bool(let b):
            return b
        case .int(let i):
            return i
        case .double(let d):
            return d
        case .string(let s):
            return s
        case .array(let arr):
            return arr.map { $0.value }
        case .dictionary(let dict):
            return dict.mapValues { $0.value }
        }
    }

    public init(_ value: Any) {
        switch value {
        case is Void:
            storage = .null
        case let b as Bool:
            storage = .bool(b)
        case let i as Int:
            storage = .int(i)
        case let d as Double:
            storage = .double(d)
        case let s as String:
            storage = .string(s)
        case let arr as [Any]:
            storage = .array(arr.map { AnyCodable($0) })
        case let dict as [String: Any]:
            storage = .dictionary(dict.mapValues { AnyCodable($0) })
        default:
            storage = .null
        }
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()

        if container.decodeNil() {
            storage = .null
        } else if let bool = try? container.decode(Bool.self) {
            storage = .bool(bool)
        } else if let int = try? container.decode(Int.self) {
            storage = .int(int)
        } else if let double = try? container.decode(Double.self) {
            storage = .double(double)
        } else if let string = try? container.decode(String.self) {
            storage = .string(string)
        } else if let array = try? container.decode([AnyCodable].self) {
            storage = .array(array)
        } else if let dictionary = try? container.decode([String: AnyCodable].self) {
            storage = .dictionary(dictionary)
        } else {
            throw DecodingError.dataCorruptedError(
                in: container,
                debugDescription: "Unable to decode value"
            )
        }
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()

        switch storage {
        case .null:
            try container.encodeNil()
        case .bool(let bool):
            try container.encode(bool)
        case .int(let int):
            try container.encode(int)
        case .double(let double):
            try container.encode(double)
        case .string(let string):
            try container.encode(string)
        case .array(let array):
            try container.encode(array)
        case .dictionary(let dictionary):
            try container.encode(dictionary)
        }
    }
}

// MARK: - HookHandlerFactory

/// Factory protocol for creating hook handlers from definitions.
public protocol HookHandlerFactory: Sendable {

    /// Creates a hook handler from a definition.
    ///
    /// - Parameter definition: The hook definition.
    /// - Returns: The created handler.
    func createHandler(for definition: HookDefinition) throws -> any HookHandler
}

/// Default hook handler factory with built-in handlers.
public struct DefaultHookHandlerFactory: HookHandlerFactory {

    /// Custom handler creators.
    private let customHandlers: [String: @Sendable (HookDefinition) throws -> any HookHandler]

    /// Creates a default factory.
    public init(
        customHandlers: [String: @Sendable (HookDefinition) throws -> any HookHandler] = [:]
    ) {
        self.customHandlers = customHandlers
    }

    public func createHandler(for definition: HookDefinition) throws -> any HookHandler {
        // Check custom handlers first
        if let creator = customHandlers[definition.type] {
            return try creator(definition)
        }

        // Built-in handlers
        switch definition.type {
        case "logging":
            return LoggingHookHandler()

        case "block":
            let reason = (definition.options?["reason"]?.value as? String) ?? "Blocked by configuration"
            return BlockingHookHandler(reason: reason)

        case "allow":
            return AllowingHookHandler()

        case "ask":
            return AskingHookHandler()

        default:
            throw HookConfigurationError.unknownHandlerType(definition.type)
        }
    }
}

// MARK: - Built-in Hook Handlers

/// A hook handler that blocks tool execution.
public struct BlockingHookHandler: HookHandler {

    private let reason: String

    public init(reason: String = "Blocked") {
        self.reason = reason
    }

    public func execute(context: HookContext) async throws -> HookResult {
        .block(reason: reason)
    }
}

/// A hook handler that allows tool execution.
public struct AllowingHookHandler: HookHandler {

    public init() {}

    public func execute(context: HookContext) async throws -> HookResult {
        .allow
    }
}

/// A hook handler that requires user approval.
public struct AskingHookHandler: HookHandler {

    public init() {}

    public func execute(context: HookContext) async throws -> HookResult {
        .ask
    }
}

// MARK: - Errors

/// Errors that can occur during hook configuration.
public enum HookConfigurationError: LocalizedError, Sendable {

    /// Unknown event type in configuration.
    case unknownEvent(String)

    /// Unknown handler type in configuration.
    case unknownHandlerType(String)

    /// Invalid handler options.
    case invalidOptions(String)

    public var errorDescription: String? {
        switch self {
        case .unknownEvent(let event):
            return "Unknown hook event: '\(event)'"
        case .unknownHandlerType(let type):
            return "Unknown hook handler type: '\(type)'"
        case .invalidOptions(let message):
            return "Invalid hook options: \(message)"
        }
    }
}

// MARK: - Presets

extension HookConfiguration {

    /// Empty configuration with no hooks.
    public static var empty: HookConfiguration {
        HookConfiguration()
    }

    /// Logging configuration - logs all tool executions.
    public static var logging: HookConfiguration {
        var config = HookConfiguration()
        config.addHook(
            HookDefinition(type: "logging", priority: 100),
            for: .preToolUse
        )
        config.addHook(
            HookDefinition(type: "logging", priority: 100),
            for: .postToolUse
        )
        config.addHook(
            HookDefinition(type: "logging"),
            for: .sessionStart
        )
        config.addHook(
            HookDefinition(type: "logging"),
            for: .sessionEnd
        )
        return config
    }
}
