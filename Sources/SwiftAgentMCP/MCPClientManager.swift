//
//  MCPClientManager.swift
//  SwiftAgentMCP
//
//  Created by SwiftAgent on 2025/01/05.
//

import Foundation

// MARK: - MCP Client Manager

/// Manages multiple MCP server connections
///
/// Features:
/// - Load configuration from `.mcp.json` files
/// - Connect to multiple servers simultaneously
/// - Enable/disable servers dynamically
/// - Get tools from all connected servers
/// - OAuth authentication management
///
/// ## Usage
///
/// ```swift
/// // Load from search paths
/// let manager = try await MCPClientManager.load(searchPaths: ["./mcp.json"])
///
/// // Or load from a specific file
/// let manager = try await MCPClientManager.load(from: URL(fileURLWithPath: ".mcp.json"))
///
/// // Get all tools from all servers
/// let tools = try await manager.allTools()
///
/// // Use with LanguageModelSession
/// let session = LanguageModelSession(model: model, tools: tools) {
///     Instructions("...")
/// }
///
/// // Server management
/// await manager.disable(serverName: "filesystem")
/// await manager.enable(serverName: "filesystem")
///
/// // Cleanup
/// await manager.disconnectAll()
/// ```
public actor MCPClientManager {

    /// Connected MCP clients by server name
    private var clients: [String: MCPClient] = [:]

    /// Server configurations for reconnection
    private var serverConfigs: [String: MCPServerConfig] = [:]

    /// Disabled server names
    private var disabledServers: Set<String> = []

    /// OAuth manager for authentication
    public let oauthManager: MCPOAuthManager

    /// Creates a new MCP client manager
    public init() {
        self.oauthManager = MCPOAuthManager()
    }

    // MARK: - Configuration Loading

    /// Loads configuration from a file and connects to all servers
    ///
    /// - Parameter configURL: The URL of the `.mcp.json` file
    /// - Returns: A configured and connected manager
    public static func load(from configURL: URL) async throws -> MCPClientManager {
        let config = try MCPConfiguration.load(from: configURL)
            .expandEnvironmentVariables()

        let manager = MCPClientManager()

        for serverConfig in config.serverConfigs() {
            await manager.storeConfig(serverConfig)
            try await manager.connect(config: serverConfig)
        }

        return manager
    }

    /// Searches for configuration in the given paths and loads the first one found
    ///
    /// - Parameter searchPaths: Ordered list of file paths to search
    /// - Returns: A configured manager (may be empty if no config found)
    public static func load(searchPaths: [String]) async throws -> MCPClientManager {
        for path in searchPaths {
            let url = URL(fileURLWithPath: path)
            if FileManager.default.fileExists(atPath: path) {
                return try await load(from: url)
            }
        }
        return MCPClientManager()
    }

    /// Stores a server configuration for later reconnection
    private func storeConfig(_ config: MCPServerConfig) {
        serverConfigs[config.name] = config
    }

    // MARK: - Server Connection

    /// Connects to an MCP server
    ///
    /// - Parameter config: The server configuration
    /// - Throws: If connection fails
    public func connect(config: MCPServerConfig) async throws {
        // Skip if disabled
        guard !disabledServers.contains(config.name) else {
            return
        }

        // Store config for reconnection
        serverConfigs[config.name] = config

        // Set up auth if needed
        if let authConfig = config.auth {
            await oauthManager.setConfig(authConfig, for: config.name)
        }

        // Connect
        let client = try await MCPClient.connect(config: config)
        clients[config.name] = client
    }

    /// Disconnects from an MCP server
    ///
    /// - Parameter serverName: The name of the server to disconnect
    public func disconnect(serverName: String) async {
        await clients[serverName]?.disconnect()
        clients.removeValue(forKey: serverName)
    }

    /// Disconnects from all servers
    public func disconnectAll() async {
        for (_, client) in clients {
            await client.disconnect()
        }
        clients.removeAll()
    }

    /// Reconnects to a server using stored configuration
    ///
    /// - Parameter serverName: The name of the server to reconnect
    /// - Throws: If reconnection fails
    public func reconnect(serverName: String) async throws {
        await disconnect(serverName: serverName)

        guard let config = serverConfigs[serverName] else {
            throw MCPClientError.serverNotFound(serverName)
        }

        try await connect(config: config)
    }

    // MARK: - Server Enable/Disable

    /// Enables a server and connects to it
    ///
    /// - Parameter serverName: The name of the server to enable
    /// - Throws: If connection fails
    public func enable(serverName: String) async throws {
        disabledServers.remove(serverName)

        // Reconnect if we have a config
        if let config = serverConfigs[serverName], clients[serverName] == nil {
            try await connect(config: config)
        }
    }

    /// Disables a server and disconnects from it
    ///
    /// - Parameter serverName: The name of the server to disable
    public func disable(serverName: String) async {
        disabledServers.insert(serverName)
        await disconnect(serverName: serverName)
    }

    /// Checks if a server is enabled
    ///
    /// - Parameter serverName: The name of the server
    /// - Returns: Whether the server is enabled
    public func isEnabled(serverName: String) -> Bool {
        !disabledServers.contains(serverName)
    }

    /// Checks if a server is connected
    ///
    /// - Parameter serverName: The name of the server
    /// - Returns: Whether the server is connected
    public func isConnected(serverName: String) -> Bool {
        clients[serverName] != nil
    }

    // MARK: - Client Access

    /// Gets a client by name
    ///
    /// - Parameter name: The server name
    /// - Returns: The client if connected
    public func client(named name: String) -> MCPClient? {
        clients[name]
    }

    // MARK: - Tools

    /// Gets all tools from all connected servers
    ///
    /// Tool names are prefixed with server name: `mcp__servername__toolname`
    ///
    /// - Returns: Array of all tools from all servers
    public func allTools() async throws -> [MCPDynamicTool] {
        var tools: [MCPDynamicTool] = []

        for (_, client) in clients {
            let serverTools = try await client.tools()
            tools.append(contentsOf: serverTools)
        }

        return tools
    }

    /// Gets tools from a specific server
    ///
    /// - Parameter serverName: The server name
    /// - Returns: Array of tools from the server
    /// - Throws: If the server is not found
    public func tools(from serverName: String) async throws -> [MCPDynamicTool] {
        guard let client = clients[serverName] else {
            throw MCPClientError.serverNotFound(serverName)
        }
        return try await client.tools()
    }

    // MARK: - Server Information

    /// Names of connected servers
    public var connectedServers: [String] {
        Array(clients.keys).sorted()
    }

    /// Names of all known servers (connected + disabled)
    public var allServers: [String] {
        Array(Set(clients.keys).union(disabledServers).union(serverConfigs.keys)).sorted()
    }

    /// Names of disabled servers
    public var disabledServerNames: [String] {
        Array(disabledServers).sorted()
    }

    /// Number of connected servers
    public var connectedCount: Int {
        clients.count
    }

    /// Server status information
    public struct ServerStatus: Sendable {
        public let name: String
        public let isConnected: Bool
        public let isEnabled: Bool
    }

    /// Gets status for all known servers
    public func serverStatuses() -> [ServerStatus] {
        allServers.map { name in
            ServerStatus(
                name: name,
                isConnected: clients[name] != nil,
                isEnabled: !disabledServers.contains(name)
            )
        }
    }
}

// MARK: - Convenience Extensions

extension MCPClientManager {

    /// Loads and connects with environment variable expansion
    ///
    /// - Parameter jsonData: The JSON configuration data
    /// - Returns: A configured manager
    public static func load(from jsonData: Data) async throws -> MCPClientManager {
        let config = try MCPConfiguration.load(from: jsonData)
            .expandEnvironmentVariables()

        let manager = MCPClientManager()

        for serverConfig in config.serverConfigs() {
            await manager.storeConfig(serverConfig)
            try await manager.connect(config: serverConfig)
        }

        return manager
    }

    /// Adds a server configuration without connecting
    ///
    /// - Parameter config: The server configuration
    public func addServer(config: MCPServerConfig) async {
        serverConfigs[config.name] = config
    }

    /// Removes a server completely
    ///
    /// - Parameter serverName: The name of the server to remove
    public func removeServer(serverName: String) async {
        await disconnect(serverName: serverName)
        serverConfigs.removeValue(forKey: serverName)
        disabledServers.remove(serverName)
    }
}
