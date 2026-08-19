import Foundation

/// Serialized HTTP authorization configuration for an MCP server.
public struct MCPAuthConfig: Codable, Sendable {
    /// Supported values are `bearer`, `basic`, and `oauth-client-credentials`.
    public let type: String
    public let tokenUrl: String?
    public let scopes: [String]?
    public let clientId: String?
    public let clientSecret: String?
    public let token: String?
    public let username: String?
    public let password: String?

    public init(
        type: String,
        tokenUrl: String? = nil,
        scopes: [String]? = nil,
        clientId: String? = nil,
        clientSecret: String? = nil,
        token: String? = nil,
        username: String? = nil,
        password: String? = nil
    ) {
        self.type = type
        self.tokenUrl = tokenUrl
        self.scopes = scopes
        self.clientId = clientId
        self.clientSecret = clientSecret
        self.token = token
        self.username = username
        self.password = password
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
        type = try container.decode(String.self, forKey: .type)
        tokenUrl = try container.decodeIfPresent(String.self, forKey: .tokenUrl)
        scopes = try container.decodeIfPresent([String].self, forKey: .scopes)
        clientId = try container.decodeIfPresent(String.self, forKey: .clientId)
        clientSecret = try container.decodeIfPresent(
            String.self,
            forKey: .clientSecret
        )
        token = try container.decodeIfPresent(String.self, forKey: .token)
        username = try container.decodeIfPresent(String.self, forKey: .username)
        password = try container.decodeIfPresent(String.self, forKey: .password)
    }

    public func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(type, forKey: .type)
        try container.encodeIfPresent(tokenUrl, forKey: .tokenUrl)
        try container.encodeIfPresent(scopes, forKey: .scopes)
        try container.encodeIfPresent(clientId, forKey: .clientId)
        try container.encodeIfPresent(clientSecret, forKey: .clientSecret)
        try container.encodeIfPresent(token, forKey: .token)
        try container.encodeIfPresent(username, forKey: .username)
        try container.encodeIfPresent(password, forKey: .password)
    }

    func expandingEnvironmentVariables(
        using environment: [String: String]
    ) throws -> MCPAuthConfig {
        MCPAuthConfig(
            type: type,
            tokenUrl: try tokenUrl.map { try MCPEnvironmentVariableExpander.expand($0, using: environment) },
            scopes: try scopes?.map { try MCPEnvironmentVariableExpander.expand($0, using: environment) },
            clientId: try clientId.map { try MCPEnvironmentVariableExpander.expand($0, using: environment) },
            clientSecret: try clientSecret.map { try MCPEnvironmentVariableExpander.expand($0, using: environment) },
            token: try token.map { try MCPEnvironmentVariableExpander.expand($0, using: environment) },
            username: try username.map { try MCPEnvironmentVariableExpander.expand($0, using: environment) },
            password: try password.map { try MCPEnvironmentVariableExpander.expand($0, using: environment) }
        )
    }

    func authorization(server: String) throws -> MCPHTTPAuthorization {
        switch type {
        case "bearer":
            guard tokenUrl == nil, scopes == nil,
                  clientId == nil, clientSecret == nil,
                  username == nil, password == nil else {
                throw MCPConfigurationError.conflictingAuthorizationFields(
                    server: server,
                    value: type
                )
            }
            guard let token, !token.isEmpty else {
                throw MCPConfigurationError.incompleteAuthorization(server: server, value: type)
            }
            try MCPHTTPHeaderPolicy.validateAuthorizationValue(
                token,
                server: server
            )
            return .bearer(token: token)

        case "basic":
            guard tokenUrl == nil, scopes == nil,
                  clientId == nil, clientSecret == nil,
                  token == nil else {
                throw MCPConfigurationError.conflictingAuthorizationFields(
                    server: server,
                    value: type
                )
            }
            guard let username, !username.isEmpty,
                  !username.contains(":"),
                  let password, !password.isEmpty else {
                throw MCPConfigurationError.incompleteAuthorization(server: server, value: type)
            }
            try MCPHTTPHeaderPolicy.validateAuthorizationValue(
                username,
                server: server
            )
            try MCPHTTPHeaderPolicy.validateAuthorizationValue(
                password,
                server: server
            )
            return .basic(username: username, password: password)

        case "oauth-client-credentials":
            guard token == nil, username == nil, password == nil else {
                throw MCPConfigurationError.conflictingAuthorizationFields(
                    server: server,
                    value: type
                )
            }
            guard let clientId, !clientId.isEmpty,
                  let clientSecret, !clientSecret.isEmpty else {
                throw MCPConfigurationError.incompleteAuthorization(server: server, value: type)
            }
            guard !clientId.contains(":") else {
                throw MCPConfigurationError.invalidAuthorizationValue(
                    server: server
                )
            }
            try MCPHTTPHeaderPolicy.validateAuthorizationValue(
                clientId,
                server: server
            )
            try MCPHTTPHeaderPolicy.validateAuthorizationValue(
                clientSecret,
                server: server
            )
            for scope in scopes ?? [] {
                try MCPHTTPHeaderPolicy.validateOAuthScope(
                    scope,
                    server: server
                )
            }
            let tokenEndpoint: URL?
            if let tokenUrl {
                guard let parsed = URL(string: tokenUrl) else {
                    throw MCPConfigurationError.invalidURL(server: server, value: tokenUrl)
                }
                guard MCPServerConfig.isSecureHTTPURL(parsed) else {
                    throw MCPConfigurationError.insecureAuthorizationEndpoint(
                        server: server,
                        value: tokenUrl
                    )
                }
                tokenEndpoint = parsed
            } else {
                tokenEndpoint = nil
            }
            return .clientCredentials(
                clientID: clientId,
                clientSecret: clientSecret,
                tokenEndpoint: tokenEndpoint,
                scopes: scopes ?? []
            )

        default:
            throw MCPConfigurationError.unsupportedAuthorization(server: server, value: type)
        }
    }

    private enum CodingKeys: String, CodingKey, CaseIterable {
        case type
        case tokenUrl
        case scopes
        case clientId
        case clientSecret
        case token
        case username
        case password
    }
}
