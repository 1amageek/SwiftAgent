//
//  ConfigurationManager.swift
//  SwiftAgent
//
//  Created by Norikazu Muramoto on 2025/01/16.
//

import Foundation

/// Global configuration manager for SwiftAgent
public final class ConfigurationManager: @unchecked Sendable {
    
    /// Shared instance
    public static let shared = ConfigurationManager()
    
    /// Configuration file paths
    public struct Paths {
        public static let homeDirectory = NSHomeDirectory()
        public static let configDirectory = "\(homeDirectory)/.swiftagent"
        public static let configFile = "\(configDirectory)/config.json"
        public static let logFile = "\(configDirectory)/swiftagent.log"
        public static let cacheDirectory = "\(configDirectory)/cache"
    }
    
    /// Environment variable keys
    public struct EnvironmentKeys {
        public static let configPath = "SWIFTAGENT_CONFIG_PATH"
        public static let logLevel = "SWIFTAGENT_LOG_LEVEL"
        public static let cacheEnabled = "SWIFTAGENT_CACHE_ENABLED"
        public static let defaultInstructions = "SWIFTAGENT_DEFAULT_INSTRUCTIONS"
    }
    
    /// Global configuration structure
    public struct GlobalConfiguration: Codable {
        public let version: String
        public let defaultInstructions: String?
        public let logLevel: LogLevel
        public let cacheEnabled: Bool
        
        public init(
            version: String = "1.0.0",
            defaultInstructions: String? = nil,
            logLevel: LogLevel = .info,
            cacheEnabled: Bool = true
        ) {
            self.version = version
            self.defaultInstructions = defaultInstructions
            self.logLevel = logLevel
            self.cacheEnabled = cacheEnabled
        }
    }
    
    /// Log levels
    public enum LogLevel: String, Codable, CaseIterable {
        case debug = "debug"
        case info = "info"
        case warning = "warning"
        case error = "error"
        case off = "off"
    }
    
    private var configuration: GlobalConfiguration
    private let fileManager = FileManager.default
    
    private init() {
        self.configuration = Self.loadConfiguration()
        createDirectoriesIfNeeded()
    }
    
    /// Load configuration from file or create default
    private static func loadConfiguration() -> GlobalConfiguration {
        let configPath = ProcessInfo.processInfo.environment[EnvironmentKeys.configPath] ?? Paths.configFile
        
        guard let data = try? Data(contentsOf: URL(fileURLWithPath: configPath)),
              let config = try? JSONDecoder().decode(GlobalConfiguration.self, from: data) else {
            return createDefaultConfiguration()
        }
        
        return config
    }
    
    /// Create default configuration with environment variable overrides
    private static func createDefaultConfiguration() -> GlobalConfiguration {
        let env = ProcessInfo.processInfo.environment
        
        // Get log level from environment
        let logLevel: LogLevel
        if let levelStr = env[EnvironmentKeys.logLevel],
           let level = LogLevel(rawValue: levelStr) {
            logLevel = level
        } else {
            logLevel = .info
        }
        
        // Get cache setting from environment
        let cacheEnabled = env[EnvironmentKeys.cacheEnabled] != "false"
        
        // Get default instructions from environment
        let defaultInstructions = env[EnvironmentKeys.defaultInstructions]
        
        return GlobalConfiguration(
            defaultInstructions: defaultInstructions,
            logLevel: logLevel,
            cacheEnabled: cacheEnabled
        )
    }
    
    /// Create necessary directories
    private func createDirectoriesIfNeeded() {
        let directories = [Paths.configDirectory, Paths.cacheDirectory]
        
        for directory in directories {
            if !fileManager.fileExists(atPath: directory) {
                try? fileManager.createDirectory(
                    atPath: directory,
                    withIntermediateDirectories: true,
                    attributes: nil
                )
            }
        }
    }
    
    /// Get current configuration
    public var currentConfiguration: GlobalConfiguration {
        return configuration
    }
    
    /// Update configuration
    public func updateConfiguration(_ newConfiguration: GlobalConfiguration) {
        self.configuration = newConfiguration
        saveConfiguration()
    }
    
    /// Save configuration to file
    private func saveConfiguration() {
        let configPath = ProcessInfo.processInfo.environment[EnvironmentKeys.configPath] ?? Paths.configFile
        
        do {
            let data = try JSONEncoder().encode(configuration)
            try data.write(to: URL(fileURLWithPath: configPath))
        } catch {
            print("Warning: Failed to save configuration: \(error)")
        }
    }
    
    
    /// Get effective instructions (considering environment overrides)
    public func getEffectiveInstructions() -> String? {
        // Check environment variable first
        if let instructions = ProcessInfo.processInfo.environment[EnvironmentKeys.defaultInstructions] {
            return instructions
        }
        
        // Fall back to configuration
        return configuration.defaultInstructions
    }
    
    
    /// Check if logging is enabled for a specific level
    public func isLogLevelEnabled(_ level: LogLevel) -> Bool {
        let levels: [LogLevel] = [.debug, .info, .warning, .error, .off]
        guard let currentIndex = levels.firstIndex(of: configuration.logLevel),
              let requestedIndex = levels.firstIndex(of: level) else {
            return false
        }
        
        return requestedIndex >= currentIndex && configuration.logLevel != .off
    }
    
    /// Log a message if the level is enabled
    public func log(_ message: String, level: LogLevel = .info) {
        guard isLogLevelEnabled(level) else { return }
        
        let timestamp = DateFormatter.logFormatter.string(from: Date())
        let logMessage = "[\(timestamp)] [\(level.rawValue.uppercased())] \(message)"
        
        print(logMessage)
        
        // Write to log file if enabled
        if configuration.cacheEnabled {
            writeToLogFile(logMessage)
        }
    }
    
    /// Write message to log file
    private func writeToLogFile(_ message: String) {
        let logPath = Paths.logFile
        let logMessage = "\(message)\n"
        
        if fileManager.fileExists(atPath: logPath) {
            if let fileHandle = FileHandle(forWritingAtPath: logPath) {
                fileHandle.seekToEndOfFile()
                fileHandle.write(logMessage.data(using: .utf8) ?? Data())
                fileHandle.closeFile()
            }
        } else {
            try? logMessage.write(toFile: logPath, atomically: true, encoding: .utf8)
        }
    }
    
    /// Reset configuration to defaults
    public func resetToDefaults() {
        configuration = Self.createDefaultConfiguration()
        saveConfiguration()
    }
    
    /// Get configuration file path
    public func getConfigurationPath() -> String {
        return ProcessInfo.processInfo.environment[EnvironmentKeys.configPath] ?? Paths.configFile
    }
    
    /// Export configuration as JSON string
    public func exportConfiguration() -> String? {
        let encoder = JSONEncoder()
        encoder.outputFormatting = .prettyPrinted
        
        guard let data = try? encoder.encode(configuration) else {
            return nil
        }
        
        return String(data: data, encoding: .utf8)
    }
    
    /// Import configuration from JSON string
    public func importConfiguration(_ jsonString: String) throws {
        guard let data = jsonString.data(using: .utf8) else {
            throw ConfigurationError.invalidJSON
        }
        
        let decoder = JSONDecoder()
        let newConfiguration = try decoder.decode(GlobalConfiguration.self, from: data)
        
        updateConfiguration(newConfiguration)
    }
}

/// Configuration-related errors
public enum ConfigurationError: Error, LocalizedError {
    case invalidJSON
    case fileNotFound(String)
    case permissionDenied(String)
    case invalidConfiguration(String)
    
    public var errorDescription: String? {
        switch self {
        case .invalidJSON:
            return "Invalid JSON configuration"
        case .fileNotFound(let path):
            return "Configuration file not found: \(path)"
        case .permissionDenied(let path):
            return "Permission denied accessing: \(path)"
        case .invalidConfiguration(let message):
            return "Invalid configuration: \(message)"
        }
    }
}

/// Extension for date formatting
extension DateFormatter {
    static let logFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd HH:mm:ss"
        return formatter
    }()
}