import Foundation

/// Serialized `.mcp.json` entry for one server.
public struct MCPServerEntry: Codable, Sendable {
    public let command: String?
    public let args: [String]?
    public let env: [String: String]?
    public let workingDirectory: String?
    public let url: String?

    /// Supported values are `stdio` and `streamable-http`.
    public let transport: String?
    public let streaming: Bool?
    public let auth: MCPAuthConfig?
    public let headers: [String: String]?
    public let disabled: Bool?
    public let startupTimeout: Int?
    public let requestTimeout: Int?
    public let toolTimeout: Int?
    public let paginationPageLimit: Int?
    public let maximumMessageBytes: Int?

    public init(
        command: String? = nil,
        args: [String]? = nil,
        env: [String: String]? = nil,
        workingDirectory: String? = nil,
        url: String? = nil,
        transport: String? = nil,
        streaming: Bool? = nil,
        auth: MCPAuthConfig? = nil,
        headers: [String: String]? = nil,
        disabled: Bool? = nil,
        startupTimeout: Int? = nil,
        requestTimeout: Int? = nil,
        toolTimeout: Int? = nil,
        paginationPageLimit: Int? = nil,
        maximumMessageBytes: Int? = nil
    ) {
        self.command = command
        self.args = args
        self.env = env
        self.workingDirectory = workingDirectory
        self.url = url
        self.transport = transport
        self.streaming = streaming
        self.auth = auth
        self.headers = headers
        self.disabled = disabled
        self.startupTimeout = startupTimeout
        self.requestTimeout = requestTimeout
        self.toolTimeout = toolTimeout
        self.paginationPageLimit = paginationPageLimit
        self.maximumMessageBytes = maximumMessageBytes
    }

    public init(from decoder: any Decoder) throws {
        let rawContainer = try decoder.container(
            keyedBy: MCPConfigurationCodingKey.self
        )
        let supportedKeys = Set(CodingKeys.allCases.map(\.rawValue))
        if let unknownKey = rawContainer.allKeys
            .map(\.stringValue)
            .filter({ !supportedKeys.contains($0) })
            .sorted()
            .first {
            throw MCPConfigurationError.unknownConfigurationField(unknownKey)
        }
        let container = try decoder.container(keyedBy: CodingKeys.self)
        if container.contains(.timeout) {
            throw MCPConfigurationError.obsoleteConfigurationField("timeout")
        }

        command = try container.decodeIfPresent(String.self, forKey: .command)
        args = try container.decodeIfPresent([String].self, forKey: .args)
        env = try container.decodeIfPresent([String: String].self, forKey: .env)
        workingDirectory = try container.decodeIfPresent(String.self, forKey: .workingDirectory)
        url = try container.decodeIfPresent(String.self, forKey: .url)
        transport = try container.decodeIfPresent(String.self, forKey: .transport)
        streaming = try container.decodeIfPresent(Bool.self, forKey: .streaming)
        auth = try container.decodeIfPresent(MCPAuthConfig.self, forKey: .auth)
        headers = try container.decodeIfPresent([String: String].self, forKey: .headers)
        disabled = try container.decodeIfPresent(Bool.self, forKey: .disabled)
        startupTimeout = try container.decodeIfPresent(Int.self, forKey: .startupTimeout)
        requestTimeout = try container.decodeIfPresent(Int.self, forKey: .requestTimeout)
        toolTimeout = try container.decodeIfPresent(Int.self, forKey: .toolTimeout)
        paginationPageLimit = try container.decodeIfPresent(Int.self, forKey: .paginationPageLimit)
        maximumMessageBytes = try container.decodeIfPresent(
            Int.self,
            forKey: .maximumMessageBytes
        )
    }

    public func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encodeIfPresent(command, forKey: .command)
        try container.encodeIfPresent(args, forKey: .args)
        try container.encodeIfPresent(env, forKey: .env)
        try container.encodeIfPresent(workingDirectory, forKey: .workingDirectory)
        try container.encodeIfPresent(url, forKey: .url)
        try container.encodeIfPresent(transport, forKey: .transport)
        try container.encodeIfPresent(streaming, forKey: .streaming)
        try container.encodeIfPresent(auth, forKey: .auth)
        try container.encodeIfPresent(headers, forKey: .headers)
        try container.encodeIfPresent(disabled, forKey: .disabled)
        try container.encodeIfPresent(startupTimeout, forKey: .startupTimeout)
        try container.encodeIfPresent(requestTimeout, forKey: .requestTimeout)
        try container.encodeIfPresent(toolTimeout, forKey: .toolTimeout)
        try container.encodeIfPresent(paginationPageLimit, forKey: .paginationPageLimit)
        try container.encodeIfPresent(
            maximumMessageBytes,
            forKey: .maximumMessageBytes
        )
    }

    func expandingEnvironmentVariables(
        using environment: [String: String]
    ) throws -> MCPServerEntry {
        MCPServerEntry(
            command: try command.map { try MCPEnvironmentVariableExpander.expand($0, using: environment) },
            args: try args?.map { try MCPEnvironmentVariableExpander.expand($0, using: environment) },
            env: try env?.mapValues { try MCPEnvironmentVariableExpander.expand($0, using: environment) },
            workingDirectory: try workingDirectory.map { try MCPEnvironmentVariableExpander.expand($0, using: environment) },
            url: try url.map { try MCPEnvironmentVariableExpander.expand($0, using: environment) },
            transport: transport,
            streaming: streaming,
            auth: try auth?.expandingEnvironmentVariables(using: environment),
            headers: try headers?.mapValues { try MCPEnvironmentVariableExpander.expand($0, using: environment) },
            disabled: disabled,
            startupTimeout: startupTimeout,
            requestTimeout: requestTimeout,
            toolTimeout: toolTimeout,
            paginationPageLimit: paginationPageLimit,
            maximumMessageBytes: maximumMessageBytes
        )
    }

    func serverConfig(name: String) throws -> MCPServerConfig {
        let selectedTransport = try transportConfig(server: name)
        let authorization = try auth?.authorization(server: name) ?? .none
        let timeoutConfig: MCPTimeoutConfig?
        if startupTimeout != nil || requestTimeout != nil || toolTimeout != nil {
            timeoutConfig = MCPTimeoutConfig(
                startup: .milliseconds(Int64(startupTimeout ?? 30_000)),
                requestExecution: .milliseconds(Int64(requestTimeout ?? 30_000)),
                toolExecution: .milliseconds(Int64(toolTimeout ?? 120_000))
            )
        } else {
            timeoutConfig = nil
        }

        return try MCPServerConfig(
            name: name,
            transport: selectedTransport,
            authorization: authorization,
            timeout: timeoutConfig,
            paginationPageLimit: paginationPageLimit ?? 1_000,
            maximumMessageBytes: maximumMessageBytes ?? 4 * 1_024 * 1_024
        )
    }

    private func transportConfig(server: String) throws -> MCPTransportConfig {
        let selected: String
        if let transport {
            selected = transport
        } else {
            switch (command, url) {
            case (.some, .none): selected = "stdio"
            case (.none, .some): selected = "streamable-http"
            default: throw MCPConfigurationError.conflictingTransportFields(server: server)
            }
        }

        switch selected {
        case "stdio":
            guard url == nil,
                  streaming == nil,
                  auth == nil,
                  headers == nil else {
                throw MCPConfigurationError.conflictingTransportFields(server: server)
            }
            guard let command, !command.isEmpty else {
                throw MCPConfigurationError.missingCommand(server: server)
            }
            return .stdio(
                command: command,
                arguments: args ?? [],
                environment: env,
                workingDirectory: workingDirectory.map { URL(fileURLWithPath: $0) }
            )

        case "streamable-http":
            guard command == nil, args == nil, env == nil, workingDirectory == nil else {
                throw MCPConfigurationError.conflictingTransportFields(server: server)
            }
            guard let url else {
                throw MCPConfigurationError.missingURL(server: server)
            }
            guard let endpoint = URL(string: url) else {
                throw MCPConfigurationError.invalidURL(server: server, value: url)
            }
            return .streamableHTTP(
                endpoint: endpoint,
                streaming: streaming ?? true,
                headers: headers ?? [:]
            )

        default:
            throw MCPConfigurationError.unsupportedTransport(server: server, value: selected)
        }
    }

    private enum CodingKeys: String, CodingKey, CaseIterable {
        case command
        case args
        case env
        case workingDirectory
        case url
        case transport
        case streaming
        case auth
        case headers
        case disabled
        case startupTimeout
        case requestTimeout
        case toolTimeout
        case paginationPageLimit
        case maximumMessageBytes
        case timeout
    }
}
