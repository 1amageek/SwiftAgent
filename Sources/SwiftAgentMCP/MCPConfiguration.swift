//
//  MCPConfiguration.swift
//  SwiftAgentMCP
//
//  Created by SwiftAgent on 2025/01/05.
//

import Foundation

// MARK: - MCP Configuration

/// Configuration for MCP servers loaded from `.mcp.json` files.
///
/// Supports Claude Code compatible configuration format:
///
/// ```json
/// {
///   "mcpServers": {
///     "github": {
///       "command": "docker",
///       "args": ["run", "-i", "--rm", "ghcr.io/github/github-mcp-server"],
///       "env": { "GITHUB_TOKEN": "${GITHUB_TOKEN}" },
///       "disabled": false
///     },
///     "slack": {
///       "url": "https://slack-mcp.example.com/sse",
///       "transport": "sse",
///       "auth": {
///         "type": "oauth2",
///         "authorizationUrl": "https://slack.com/oauth/v2/authorize",
///         "tokenUrl": "https://slack.com/api/oauth.v2.access",
///         "scopes": ["channels:read", "chat:write"]
///       },
///       "headers": {
///         "X-Custom-Header": "value"
///       }
///     }
///   }
/// }
/// ```
public struct MCPConfiguration: Codable, Sendable {

    /// Server configurations keyed by server name
    public let mcpServers: [String: MCPServerEntry]

    /// Creates a new MCP configuration
    public init(mcpServers: [String: MCPServerEntry] = [:]) {
        self.mcpServers = mcpServers
    }

    // MARK: - Loading

    /// Loads configuration from a file URL
    /// - Parameter url: The file URL to load from
    /// - Returns: The parsed configuration
    /// - Throws: If the file cannot be read or parsed
    public static func load(from url: URL) throws -> MCPConfiguration {
        let data = try Data(contentsOf: url)
        return try load(from: data)
    }

    /// Loads configuration from JSON data
    /// - Parameter data: The JSON data to parse
    /// - Returns: The parsed configuration
    /// - Throws: If the data cannot be parsed
    public static func load(from data: Data) throws -> MCPConfiguration {
        let decoder = JSONDecoder()
        return try decoder.decode(MCPConfiguration.self, from: data)
    }

    /// Searches for configuration in default locations and loads it
    ///
    /// Search order:
    /// 1. `./.mcp.json` (project directory)
    /// 2. `~/.config/claude/.mcp.json` (user directory)
    ///
    /// - Returns: The configuration if found, nil otherwise
    public static func loadDefault() throws -> MCPConfiguration? {
        let searchPaths = [
            FileManager.default.currentDirectoryPath + "/.mcp.json",
            FileManager.default.homeDirectoryForCurrentUser.path + "/.config/claude/.mcp.json"
        ]

        for path in searchPaths {
            if FileManager.default.fileExists(atPath: path) {
                return try load(from: URL(fileURLWithPath: path))
            }
        }

        return nil
    }

    // MARK: - Environment Variable Expansion

    /// Returns a new configuration with environment variables expanded
    ///
    /// Environment variables in the format `${VAR_NAME}` are replaced
    /// with their values from the current process environment.
    ///
    /// - Returns: A new configuration with expanded values
    public func expandEnvironmentVariables() -> MCPConfiguration {
        var expandedServers: [String: MCPServerEntry] = [:]

        for (name, entry) in mcpServers {
            expandedServers[name] = entry.expandEnvironmentVariables()
        }

        return MCPConfiguration(mcpServers: expandedServers)
    }

    // MARK: - Conversion

    /// Converts the configuration to an array of MCPServerConfig
    ///
    /// Disabled servers are excluded from the result.
    ///
    /// - Returns: Array of server configurations ready for connection
    public func serverConfigs() -> [MCPServerConfig] {
        mcpServers.compactMap { name, entry in
            // Skip disabled servers
            if entry.disabled == true {
                return nil
            }
            return entry.toServerConfig(name: name)
        }
    }
}

// MARK: - Server Entry

extension MCPConfiguration {

    /// Configuration entry for a single MCP server
    public struct MCPServerEntry: Codable, Sendable {

        // MARK: - Stdio Transport

        /// Executable command for stdio transport
        public let command: String?

        /// Arguments for the command
        public let args: [String]?

        /// Environment variables for the subprocess
        public let env: [String: String]?

        /// Working directory for the subprocess
        public let workingDirectory: String?

        // MARK: - HTTP/SSE Transport

        /// URL for HTTP or SSE transport
        public let url: String?

        /// Transport type: "stdio", "http", or "sse"
        public let transport: String?

        // MARK: - Authentication

        /// Authentication configuration
        public let auth: MCPAuthConfig?

        // MARK: - Custom Headers

        /// Custom headers for HTTP/SSE requests
        public let headers: [String: String]?

        // MARK: - Server Control

        /// Whether the server is disabled
        public let disabled: Bool?

        // MARK: - Timeout

        /// Server startup timeout in milliseconds
        public let timeout: Int?

        /// Tool execution timeout in milliseconds
        public let toolTimeout: Int?

        // MARK: - Initialization

        public init(
            command: String? = nil,
            args: [String]? = nil,
            env: [String: String]? = nil,
            workingDirectory: String? = nil,
            url: String? = nil,
            transport: String? = nil,
            auth: MCPAuthConfig? = nil,
            headers: [String: String]? = nil,
            disabled: Bool? = nil,
            timeout: Int? = nil,
            toolTimeout: Int? = nil
        ) {
            self.command = command
            self.args = args
            self.env = env
            self.workingDirectory = workingDirectory
            self.url = url
            self.transport = transport
            self.auth = auth
            self.headers = headers
            self.disabled = disabled
            self.timeout = timeout
            self.toolTimeout = toolTimeout
        }

        // MARK: - Environment Expansion

        func expandEnvironmentVariables() -> MCPServerEntry {
            MCPServerEntry(
                command: command?.expandingEnvironmentVariables(),
                args: args?.map { $0.expandingEnvironmentVariables() },
                env: env?.mapValues { $0.expandingEnvironmentVariables() },
                workingDirectory: workingDirectory?.expandingEnvironmentVariables(),
                url: url?.expandingEnvironmentVariables(),
                transport: transport,
                auth: auth?.expandEnvironmentVariables(),
                headers: headers?.mapValues { $0.expandingEnvironmentVariables() },
                disabled: disabled,
                timeout: timeout,
                toolTimeout: toolTimeout
            )
        }

        // MARK: - Conversion

        func toServerConfig(name: String) -> MCPServerConfig? {
            let transportConfig: MCPTransportConfig

            // Determine transport type
            let transportType = transport ?? (command != nil ? "stdio" : "http")

            switch transportType {
            case "stdio":
                guard let command = command else { return nil }
                transportConfig = .stdio(
                    command: command,
                    arguments: args ?? [],
                    environment: env,
                    workingDirectory: workingDirectory.map { URL(fileURLWithPath: $0) }
                )

            case "http":
                guard let urlString = url, let endpoint = URL(string: urlString) else { return nil }
                transportConfig = .http(
                    endpoint: endpoint,
                    headers: headers ?? [:]
                )

            case "sse":
                guard let urlString = url, let endpoint = URL(string: urlString) else { return nil }
                transportConfig = .sse(
                    endpoint: endpoint,
                    headers: headers ?? [:],
                    autoReconnect: true
                )

            default:
                return nil
            }

            // Create timeout config if specified
            var timeoutConfig: MCPTimeoutConfig? = nil
            if timeout != nil || toolTimeout != nil {
                timeoutConfig = MCPTimeoutConfig(
                    startup: timeout.map { Duration.milliseconds($0) } ?? .seconds(30),
                    toolExecution: toolTimeout.map { Duration.milliseconds($0) } ?? .seconds(120)
                )
            }

            return MCPServerConfig(
                name: name,
                transport: transportConfig,
                auth: auth,
                timeout: timeoutConfig
            )
        }
    }
}

// MARK: - Auth Configuration

extension MCPConfiguration {

    /// Authentication configuration for MCP servers
    public struct MCPAuthConfig: Codable, Sendable {

        /// Authentication type: "oauth2", "bearer", "basic"
        public let type: String

        /// OAuth2: Authorization endpoint URL
        public let authorizationUrl: String?

        /// OAuth2: Token endpoint URL
        public let tokenUrl: String?

        /// OAuth2: Requested scopes
        public let scopes: [String]?

        /// OAuth2: Client ID
        public let clientId: String?

        /// OAuth2: Client secret
        public let clientSecret: String?

        /// Bearer: Static token
        public let token: String?

        /// Basic: Username
        public let username: String?

        /// Basic: Password
        public let password: String?

        public init(
            type: String,
            authorizationUrl: String? = nil,
            tokenUrl: String? = nil,
            scopes: [String]? = nil,
            clientId: String? = nil,
            clientSecret: String? = nil,
            token: String? = nil,
            username: String? = nil,
            password: String? = nil
        ) {
            self.type = type
            self.authorizationUrl = authorizationUrl
            self.tokenUrl = tokenUrl
            self.scopes = scopes
            self.clientId = clientId
            self.clientSecret = clientSecret
            self.token = token
            self.username = username
            self.password = password
        }

        func expandEnvironmentVariables() -> MCPAuthConfig {
            MCPAuthConfig(
                type: type,
                authorizationUrl: authorizationUrl?.expandingEnvironmentVariables(),
                tokenUrl: tokenUrl?.expandingEnvironmentVariables(),
                scopes: scopes,
                clientId: clientId?.expandingEnvironmentVariables(),
                clientSecret: clientSecret?.expandingEnvironmentVariables(),
                token: token?.expandingEnvironmentVariables(),
                username: username?.expandingEnvironmentVariables(),
                password: password?.expandingEnvironmentVariables()
            )
        }
    }
}

// MARK: - String Extension for Environment Variable Expansion

private extension String {

    /// Expands environment variables in the format `${VAR_NAME}`
    func expandingEnvironmentVariables() -> String {
        var result = self
        let pattern = #"\$\{([^}]+)\}"#

        guard let regex = try? NSRegularExpression(pattern: pattern) else {
            return self
        }

        let range = NSRange(startIndex..., in: self)
        let matches = regex.matches(in: self, range: range)

        // Process in reverse order to maintain correct indices
        for match in matches.reversed() {
            guard let varRange = Range(match.range(at: 1), in: self),
                  let fullRange = Range(match.range, in: self) else {
                continue
            }

            let varName = String(self[varRange])
            if let value = ProcessInfo.processInfo.environment[varName] {
                result.replaceSubrange(fullRange, with: value)
            }
        }

        return result
    }
}
