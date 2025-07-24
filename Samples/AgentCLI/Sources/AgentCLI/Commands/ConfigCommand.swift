//
//  ConfigCommand.swift
//  SwiftAgent
//
//  Created by Norikazu Muramoto on 2025/01/16.
//

import Foundation
import ArgumentParser

/// Configuration management command
extension AgentCommand {
    
    struct Config: AsyncParsableCommand {
        static let configuration = CommandConfiguration(
            commandName: "config",
            abstract: "Manage SwiftAgent configuration",
            subcommands: [Show.self, Set.self, Reset.self, Export.self, Import.self]
        )
        
        mutating func run() async throws {
            // Show current configuration by default
            var showCommand = Show()
            try await showCommand.run()
        }
        
        // Show configuration
        struct Show: AsyncParsableCommand {
            static let configuration = CommandConfiguration(
                commandName: "show",
                abstract: "Show current configuration"
            )
            
            @Flag(name: .shortAndLong, help: "Show configuration as JSON")
            var json: Bool = false
            
            mutating func run() async throws {
                let config = ConfigurationManager.shared.currentConfiguration
                
                if json {
                    if let jsonString = ConfigurationManager.shared.exportConfiguration() {
                        print(jsonString)
                    }
                } else {
                    print("SwiftAgent Configuration:")
                    print("  Version: \(config.version)")
                    if let instructions = config.defaultInstructions {
                        print("  Default Instructions: \(instructions)")
                    }
                    print("  Log Level: \(config.logLevel.rawValue)")
                    print("  Cache Enabled: \(config.cacheEnabled)")
                    print("  Configuration File: \(ConfigurationManager.shared.getConfigurationPath())")
                }
            }
        }
        
        // Set configuration value
        struct Set: AsyncParsableCommand {
            static let configuration = CommandConfiguration(
                commandName: "set",
                abstract: "Set configuration value"
            )
            
            @Argument(help: "Configuration key (instructions, loglevel, cache)")
            var key: String
            
            @Argument(help: "Configuration value")
            var value: String
            
            mutating func run() async throws {
                var config = ConfigurationManager.shared.currentConfiguration
                
                switch key.lowercased() {
                case "instructions":
                    config = ConfigurationManager.GlobalConfiguration(
                        version: config.version,
                        defaultInstructions: value.isEmpty ? nil : value,
                        logLevel: config.logLevel,
                        cacheEnabled: config.cacheEnabled
                    )
                    
                case "loglevel":
                    guard let logLevel = ConfigurationManager.LogLevel(rawValue: value) else {
                        throw ValidationError("Invalid log level: \(value). Available: \(ConfigurationManager.LogLevel.allCases.map { $0.rawValue }.joined(separator: ", "))")
                    }
                    config = ConfigurationManager.GlobalConfiguration(
                        version: config.version,
                        defaultInstructions: config.defaultInstructions,
                        logLevel: logLevel,
                        cacheEnabled: config.cacheEnabled
                    )
                    
                case "cache":
                    let cacheEnabled = value.lowercased() == "true" || value == "1"
                    config = ConfigurationManager.GlobalConfiguration(
                        version: config.version,
                        defaultInstructions: config.defaultInstructions,
                        logLevel: config.logLevel,
                        cacheEnabled: cacheEnabled
                    )
                    
                default:
                    throw ValidationError("Unknown configuration key: \(key). Available: instructions, loglevel, cache")
                }
                
                ConfigurationManager.shared.updateConfiguration(config)
                print("Configuration updated: \(key) = \(value)")
            }
        }
        
        // Reset configuration
        struct Reset: AsyncParsableCommand {
            static let configuration = CommandConfiguration(
                commandName: "reset",
                abstract: "Reset configuration to defaults"
            )
            
            @Flag(name: .shortAndLong, help: "Force reset without confirmation")
            var force: Bool = false
            
            mutating func run() async throws {
                if !force {
                    print("This will reset all configuration to defaults. Continue? (y/N): ", terminator: "")
                    let response = readLine()?.lowercased()
                    guard response == "y" || response == "yes" else {
                        print("Reset cancelled.")
                        return
                    }
                }
                
                ConfigurationManager.shared.resetToDefaults()
                print("Configuration reset to defaults.")
            }
        }
        
        // Export configuration
        struct Export: AsyncParsableCommand {
            static let configuration = CommandConfiguration(
                commandName: "export",
                abstract: "Export configuration to file"
            )
            
            @Argument(help: "Output file path")
            var outputPath: String
            
            @Flag(name: .shortAndLong, help: "Overwrite existing file")
            var force: Bool = false
            
            mutating func run() async throws {
                let url = URL(fileURLWithPath: outputPath)
                
                if FileManager.default.fileExists(atPath: outputPath) && !force {
                    throw ValidationError("File already exists: \(outputPath). Use --force to overwrite.")
                }
                
                guard let jsonString = ConfigurationManager.shared.exportConfiguration() else {
                    throw ValidationError("Failed to export configuration")
                }
                
                try jsonString.write(to: url, atomically: true, encoding: .utf8)
                print("Configuration exported to: \(outputPath)")
            }
        }
        
        // Import configuration
        struct Import: AsyncParsableCommand {
            static let configuration = CommandConfiguration(
                commandName: "import",
                abstract: "Import configuration from file"
            )
            
            @Argument(help: "Input file path")
            var inputPath: String
            
            @Flag(name: .shortAndLong, help: "Force import without confirmation")
            var force: Bool = false
            
            mutating func run() async throws {
                let url = URL(fileURLWithPath: inputPath)
                
                guard FileManager.default.fileExists(atPath: inputPath) else {
                    throw ValidationError("File not found: \(inputPath)")
                }
                
                let jsonString = try String(contentsOf: url, encoding: .utf8)
                
                if !force {
                    print("This will overwrite current configuration. Continue? (y/N): ", terminator: "")
                    let response = readLine()?.lowercased()
                    guard response == "y" || response == "yes" else {
                        print("Import cancelled.")
                        return
                    }
                }
                
                try ConfigurationManager.shared.importConfiguration(jsonString)
                print("Configuration imported from: \(inputPath)")
            }
        }
    }
}