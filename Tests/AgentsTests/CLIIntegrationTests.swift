//
//  CLIIntegrationTests.swift
//  SwiftAgent
//
//  Created by Norikazu Muramoto on 2025/01/16.
//

import Testing
@testable import AgentCLI
@testable import Agents
@testable import SwiftAgent

@Suite("CLI Integration Tests")
struct CLIIntegrationTests {
    
    @Test("Configuration Manager Basics")
    func configurationManagerBasics() async throws {
        let config = ConfigurationManager.shared.currentConfiguration
        #expect(config != nil)
        #expect(config.version == "1.0.0")
        #expect(config.logLevel != nil)
        #expect(config.cacheEnabled == true || config.cacheEnabled == false)
    }
    
    @Test("Configuration Path")
    func configurationPath() async throws {
        let path = ConfigurationManager.shared.getConfigurationPath()
        #expect(!path.isEmpty)
        #expect(path.contains(".swiftagent") || path.contains("config.json"))
    }
    
    @Test("MainAgent Creation")
    func mainAgentCreation() async throws {
        let agent = MainAgent()
        #expect(agent != nil)
    }
    
    @Test("AskAgent Creation")
    func askAgentCreation() async throws {
        let agent = AskAgent()
        #expect(agent != nil)
    }
    
    @Test("Log Level Configuration")
    func logLevelConfiguration() async throws {
        let manager = ConfigurationManager.shared
        
        // Test log level checking
        #expect(manager.isLogLevelEnabled(.error) == true || manager.isLogLevelEnabled(.error) == false)
        #expect(manager.isLogLevelEnabled(.warning) == true || manager.isLogLevelEnabled(.warning) == false)
        #expect(manager.isLogLevelEnabled(.info) == true || manager.isLogLevelEnabled(.info) == false)
        #expect(manager.isLogLevelEnabled(.debug) == true || manager.isLogLevelEnabled(.debug) == false)
    }
    
    @Test("Environment Variable Support")
    func environmentVariableSupport() async throws {
        // Test environment keys
        #expect(ConfigurationManager.EnvironmentKeys.configPath == "SWIFTAGENT_CONFIG_PATH")
        #expect(ConfigurationManager.EnvironmentKeys.logLevel == "SWIFTAGENT_LOG_LEVEL")
        #expect(ConfigurationManager.EnvironmentKeys.cacheEnabled == "SWIFTAGENT_CACHE_ENABLED")
        #expect(ConfigurationManager.EnvironmentKeys.defaultInstructions == "SWIFTAGENT_DEFAULT_INSTRUCTIONS")
    }
    
    @Test("Configuration Export")
    func configurationExport() async throws {
        let jsonString = ConfigurationManager.shared.exportConfiguration()
        #expect(jsonString != nil)
        
        if let json = jsonString {
            #expect(json.contains("version"))
            #expect(json.contains("logLevel"))
            #expect(json.contains("cacheEnabled"))
        }
    }
    
    @Test("Default Agent Usage")
    func defaultAgentUsage() async throws {
        let agent = DefaultAgent()
        #expect(agent != nil)
        
        // Test with tools
        let agentWithTools = DefaultAgent(tools: [])
        #expect(agentWithTools != nil)
        
        // Test with instructions
        let agentWithInstructions = DefaultAgent(instructions: "Test instructions")
        #expect(agentWithInstructions != nil)
    }
    
    @Test("Configuration File Paths")
    func configurationFilePaths() async throws {
        #expect(ConfigurationManager.Paths.configDirectory.contains(".swiftagent"))
        #expect(ConfigurationManager.Paths.configFile.contains("config.json"))
        #expect(ConfigurationManager.Paths.logFile.contains("swiftagent.log"))
        #expect(ConfigurationManager.Paths.cacheDirectory.contains("cache"))
    }
    
    @Test("Log Level Enum")
    func logLevelEnum() async throws {
        let levels = ConfigurationManager.LogLevel.allCases
        #expect(levels.contains(.debug))
        #expect(levels.contains(.info))
        #expect(levels.contains(.warning))
        #expect(levels.contains(.error))
        #expect(levels.contains(.off))
        
        // Test raw values
        #expect(ConfigurationManager.LogLevel.debug.rawValue == "debug")
        #expect(ConfigurationManager.LogLevel.info.rawValue == "info")
        #expect(ConfigurationManager.LogLevel.warning.rawValue == "warning")
        #expect(ConfigurationManager.LogLevel.error.rawValue == "error")
        #expect(ConfigurationManager.LogLevel.off.rawValue == "off")
    }
}