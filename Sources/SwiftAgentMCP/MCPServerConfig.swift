import Foundation

/// Fully validated configuration for one MCP connection.
public struct MCPServerConfig: Sendable {
    public let name: String
    public let transport: MCPTransportConfig
    public let authorization: MCPHTTPAuthorization
    public let timeout: MCPTimeoutConfig?
    public let paginationPageLimit: Int
    public let maximumMessageBytes: Int

    public init(
        name: String,
        transport: MCPTransportConfig,
        authorization: MCPHTTPAuthorization = .none,
        timeout: MCPTimeoutConfig? = nil,
        paginationPageLimit: Int = 1_000,
        maximumMessageBytes: Int = 4 * 1_024 * 1_024
    ) throws {
        guard !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw MCPConfigurationError.emptyServerName
        }
        guard MCPToolNamespace.isValidServerName(name) else {
            throw MCPConfigurationError.invalidServerName(name)
        }
        if let timeout {
            guard timeout.startup > .zero,
                  timeout.requestExecution > .zero,
                  timeout.toolExecution > .zero else {
                throw MCPConfigurationError.nonPositiveTimeout(server: name)
            }
        }
        guard paginationPageLimit > 0 else {
            throw MCPConfigurationError.nonPositivePaginationLimit(server: name)
        }
        guard maximumMessageBytes > 0 else {
            throw MCPConfigurationError.nonPositiveMessageLimit(server: name)
        }
        try Self.validate(transport: transport, server: name)
        try authorization.validate(server: name)
        if case .stdio = transport {
            guard case .none = authorization else {
                throw MCPConfigurationError.authorizationNotSupported(
                    server: name,
                    transport: "stdio"
                )
            }
        }

        self.name = name
        self.transport = transport
        self.authorization = authorization
        self.timeout = timeout
        self.paginationPageLimit = paginationPageLimit
        self.maximumMessageBytes = maximumMessageBytes
    }

    private static func validate(
        transport: MCPTransportConfig,
        server: String
    ) throws {
        switch transport {
        case .stdio(let command, _, _, let workingDirectory):
            #if os(macOS) || os(Linux)
            guard !command.isEmpty else {
                throw MCPConfigurationError.missingCommand(server: server)
            }
            if let workingDirectory, !workingDirectory.isFileURL {
                throw MCPConfigurationError.invalidWorkingDirectory(
                    server: server,
                    value: workingDirectory.absoluteString
                )
            }
            #else
            throw MCPConfigurationError.unsupportedTransport(
                server: server,
                value: "stdio child processes on this platform"
            )
            #endif

        case .streamableHTTP(let endpoint, _, let headers):
            guard Self.isSecureHTTPURL(endpoint) else {
                throw MCPConfigurationError.insecureEndpoint(
                    server: server,
                    value: endpoint.absoluteString
                )
            }
            try MCPHTTPHeaderPolicy.validate(headers, server: server)
        }
    }

    static func isSecureHTTPURL(_ url: URL) -> Bool {
        guard url.user == nil, url.password == nil, url.fragment == nil,
              let scheme = url.scheme?.lowercased(),
              let host = url.host?.lowercased(),
              !host.isEmpty else {
            return false
        }
        if let port = url.port, !(1...65_535).contains(port) {
            return false
        }
        if scheme == "https" {
            return true
        }
        guard scheme == "http" else {
            return false
        }
        return host == "localhost"
            || host == "127.0.0.1"
            || host == "::1"
            || host == "[::1]"
    }
}
