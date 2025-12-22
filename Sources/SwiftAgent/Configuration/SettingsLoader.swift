//
//  SettingsLoader.swift
//  SwiftAgent
//
//  Created by SwiftAgent on 2025/01/23.
//

import Foundation

/// Unified settings structure for agent configuration.
///
/// This structure matches the JSON format used in settings files.
///
/// ## File Format
///
/// ```json
/// {
///   "permissions": {
///     "defaultMode": "default",
///     "allow": ["Read", "Glob", "Grep"],
///     "deny": ["Bash(rm -rf:*)"],
///     "ask": ["Edit", "Write"]
///   },
///   "hooks": {
///     "preToolUse": [
///       {"type": "logging", "priority": 100}
///     ],
///     "postToolUse": [
///       {"type": "logging"}
///     ]
///   }
/// }
/// ```
public struct AgentSettings: Codable, Sendable {

    /// Permission configuration.
    public var permissions: PermissionConfiguration?

    /// Hook configuration.
    public var hooks: HookConfiguration?

    /// Creates settings.
    public init(
        permissions: PermissionConfiguration? = nil,
        hooks: HookConfiguration? = nil
    ) {
        self.permissions = permissions
        self.hooks = hooks
    }
}

// MARK: - SettingsLoader

/// Loads agent settings from various sources.
///
/// `SettingsLoader` handles loading settings from JSON files,
/// environment variables, and default locations.
///
/// ## Standard Locations
///
/// Settings are searched in the following order:
/// 1. `./.agent/settings.json` (project-level)
/// 2. `~/.agent/settings.json` (user-level)
/// 3. Environment variable `AGENT_SETTINGS_PATH`
///
/// ## Usage
///
/// ```swift
/// // Load from default locations
/// let settings = try SettingsLoader.loadFromDefaultLocations()
///
/// // Load from specific file
/// let settings = try SettingsLoader.load(from: "/path/to/settings.json")
///
/// // Apply to managers
/// await settings.permissions?.apply(to: permissionManager)
/// try await settings.hooks?.apply(to: hookManager, handlerFactory: factory)
/// ```
public enum SettingsLoader {

    // MARK: - Standard Paths

    /// Project-level settings path.
    public static let projectSettingsPath = ".agent/settings.json"

    /// User-level settings path.
    public static var userSettingsPath: String {
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        return "\(home)/.agent/settings.json"
    }

    /// Environment variable for custom settings path.
    public static let settingsEnvVar = "AGENT_SETTINGS_PATH"

    // MARK: - Loading

    /// Loads settings from a file path.
    ///
    /// - Parameter path: The path to the settings file.
    /// - Returns: The loaded settings.
    public static func load(from path: String) throws -> AgentSettings {
        let url = URL(fileURLWithPath: path)
        let data = try Data(contentsOf: url)
        let decoder = JSONDecoder()
        return try decoder.decode(AgentSettings.self, from: data)
    }

    /// Loads settings from a URL.
    ///
    /// - Parameter url: The URL to the settings file.
    /// - Returns: The loaded settings.
    public static func load(from url: URL) throws -> AgentSettings {
        let data = try Data(contentsOf: url)
        let decoder = JSONDecoder()
        return try decoder.decode(AgentSettings.self, from: data)
    }

    /// Loads settings from JSON data.
    ///
    /// - Parameter data: The JSON data.
    /// - Returns: The loaded settings.
    public static func load(from data: Data) throws -> AgentSettings {
        let decoder = JSONDecoder()
        return try decoder.decode(AgentSettings.self, from: data)
    }

    /// Loads settings from a JSON string.
    ///
    /// - Parameter json: The JSON string.
    /// - Returns: The loaded settings.
    public static func loadFromJSON(_ json: String) throws -> AgentSettings {
        guard let data = json.data(using: .utf8) else {
            throw SettingsError.invalidJSON("Unable to convert string to data")
        }
        return try load(from: data)
    }

    /// Loads settings from default locations.
    ///
    /// Searches in order:
    /// 1. Environment variable path
    /// 2. Project-level settings
    /// 3. User-level settings
    ///
    /// - Returns: The loaded settings, or empty settings if no file found.
    public static func loadFromDefaultLocations() throws -> AgentSettings {
        let fm = FileManager.default

        // 1. Environment variable
        if let envPath = ProcessInfo.processInfo.environment[settingsEnvVar],
           fm.fileExists(atPath: envPath) {
            return try load(from: envPath)
        }

        // 2. Project-level
        let projectPath = fm.currentDirectoryPath + "/" + projectSettingsPath
        if fm.fileExists(atPath: projectPath) {
            return try load(from: projectPath)
        }

        // 3. User-level
        if fm.fileExists(atPath: userSettingsPath) {
            return try load(from: userSettingsPath)
        }

        // No settings found - return empty
        return AgentSettings()
    }

    /// Loads and merges settings from multiple locations.
    ///
    /// User-level settings are loaded first, then project-level settings
    /// are merged on top (project settings take precedence).
    ///
    /// - Returns: The merged settings.
    public static func loadMergedSettings() throws -> AgentSettings {
        let fm = FileManager.default
        var settings = AgentSettings()

        // Load user-level first (lower priority)
        if fm.fileExists(atPath: userSettingsPath) {
            let userSettings = try load(from: userSettingsPath)
            settings = merge(base: settings, override: userSettings)
        }

        // Load project-level (higher priority)
        let projectPath = fm.currentDirectoryPath + "/" + projectSettingsPath
        if fm.fileExists(atPath: projectPath) {
            let projectSettings = try load(from: projectPath)
            settings = merge(base: settings, override: projectSettings)
        }

        // Environment variable has highest priority
        if let envPath = ProcessInfo.processInfo.environment[settingsEnvVar],
           fm.fileExists(atPath: envPath) {
            let envSettings = try load(from: envPath)
            settings = merge(base: settings, override: envSettings)
        }

        return settings
    }

    // MARK: - Merging

    /// Merges two settings, with override taking precedence.
    private static func merge(base: AgentSettings, override: AgentSettings) -> AgentSettings {
        var result = base

        // Merge permissions
        if let overridePermissions = override.permissions {
            if var basePermissions = result.permissions {
                // Merge arrays
                basePermissions.allow = mergeArrays(basePermissions.allow, overridePermissions.allow)
                basePermissions.deny = mergeArrays(basePermissions.deny, overridePermissions.deny)
                basePermissions.ask = mergeArrays(basePermissions.ask, overridePermissions.ask)

                // Override mode if specified
                if overridePermissions.defaultMode != .default {
                    basePermissions.defaultMode = overridePermissions.defaultMode
                }

                // Override levels
                if let overrideMaxLevel = overridePermissions.maxLevel {
                    basePermissions.maxLevel = overrideMaxLevel
                }
                if let overrideToolLevels = overridePermissions.toolLevels {
                    var merged = basePermissions.toolLevels ?? [:]
                    for (key, value) in overrideToolLevels {
                        merged[key] = value
                    }
                    basePermissions.toolLevels = merged
                }

                result.permissions = basePermissions
            } else {
                result.permissions = overridePermissions
            }
        }

        // Merge hooks
        if let overrideHooks = override.hooks {
            if var baseHooks = result.hooks {
                // Merge hook definitions by event
                for (event, definitions) in overrideHooks.hooks {
                    if baseHooks.hooks[event] != nil {
                        baseHooks.hooks[event]?.append(contentsOf: definitions)
                    } else {
                        baseHooks.hooks[event] = definitions
                    }
                }
                result.hooks = baseHooks
            } else {
                result.hooks = overrideHooks
            }
        }

        return result
    }

    private static func mergeArrays(_ base: [String], _ override: [String]) -> [String] {
        var result = base
        for item in override where !result.contains(item) {
            result.append(item)
        }
        return result
    }

    // MARK: - Saving

    /// Saves settings to a file.
    ///
    /// - Parameters:
    ///   - settings: The settings to save.
    ///   - path: The file path.
    ///   - prettyPrint: Whether to format the JSON nicely.
    public static func save(_ settings: AgentSettings, to path: String, prettyPrint: Bool = true) throws {
        let encoder = JSONEncoder()
        if prettyPrint {
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        }

        let data = try encoder.encode(settings)
        let url = URL(fileURLWithPath: path)

        // Create directory if needed
        let directory = url.deletingLastPathComponent()
        try FileManager.default.createDirectory(
            at: directory,
            withIntermediateDirectories: true
        )

        try data.write(to: url)
    }

    // MARK: - Validation

    /// Validates settings.
    ///
    /// - Parameter settings: The settings to validate.
    /// - Returns: Array of validation errors (empty if valid).
    public static func validate(_ settings: AgentSettings) -> [SettingsValidationError] {
        var errors: [SettingsValidationError] = []

        // Validate permission patterns
        if let permissions = settings.permissions {
            for pattern in permissions.allow {
                if !isValidPattern(pattern) {
                    errors.append(.invalidPermissionPattern(pattern))
                }
            }
            for pattern in permissions.deny {
                if !isValidPattern(pattern) {
                    errors.append(.invalidPermissionPattern(pattern))
                }
            }
            for pattern in permissions.ask {
                if !isValidPattern(pattern) {
                    errors.append(.invalidPermissionPattern(pattern))
                }
            }
        }

        // Validate hook events
        if let hooks = settings.hooks {
            for eventName in hooks.hooks.keys {
                if HookEvent(rawValue: eventName) == nil {
                    errors.append(.unknownHookEvent(eventName))
                }
            }
        }

        return errors
    }

    private static func isValidPattern(_ pattern: String) -> Bool {
        // Basic validation - pattern should not be empty
        !pattern.trimmingCharacters(in: .whitespaces).isEmpty
    }
}

// MARK: - Errors

/// Errors that can occur during settings loading.
public enum SettingsError: LocalizedError, Sendable {

    /// The settings file was not found.
    case fileNotFound(String)

    /// The JSON is invalid.
    case invalidJSON(String)

    /// The settings structure is invalid.
    case invalidStructure(String)

    public var errorDescription: String? {
        switch self {
        case .fileNotFound(let path):
            return "Settings file not found: \(path)"
        case .invalidJSON(let message):
            return "Invalid JSON: \(message)"
        case .invalidStructure(let message):
            return "Invalid settings structure: \(message)"
        }
    }
}

/// Validation errors for settings.
public enum SettingsValidationError: LocalizedError, Sendable {

    /// Invalid permission pattern.
    case invalidPermissionPattern(String)

    /// Unknown hook event.
    case unknownHookEvent(String)

    /// Unknown handler type.
    case unknownHandlerType(String)

    public var errorDescription: String? {
        switch self {
        case .invalidPermissionPattern(let pattern):
            return "Invalid permission pattern: '\(pattern)'"
        case .unknownHookEvent(let event):
            return "Unknown hook event: '\(event)'"
        case .unknownHandlerType(let type):
            return "Unknown handler type: '\(type)'"
        }
    }
}

// MARK: - AgentSettings Extensions

extension AgentSettings {

    /// Creates settings with default permission configuration.
    public static func withPermissions(_ permissions: PermissionConfiguration) -> AgentSettings {
        AgentSettings(permissions: permissions, hooks: nil)
    }

    /// Creates settings with default hook configuration.
    public static func withHooks(_ hooks: HookConfiguration) -> AgentSettings {
        AgentSettings(permissions: nil, hooks: hooks)
    }

    /// Creates development settings.
    public static var development: AgentSettings {
        AgentSettings(
            permissions: .development,
            hooks: .logging
        )
    }

    /// Creates restrictive settings.
    public static var restrictive: AgentSettings {
        AgentSettings(
            permissions: .restrictive,
            hooks: .logging
        )
    }

    /// Creates permissive settings.
    public static var permissive: AgentSettings {
        AgentSettings(
            permissions: .permissive,
            hooks: nil
        )
    }
}
