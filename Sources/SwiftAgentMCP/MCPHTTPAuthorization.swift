import Foundation
import MCP

/// Creates HTTP authorization state for exactly one MCP transport.
public enum MCPHTTPAuthorization: Sendable {
    case none
    case bearer(token: String)
    case basic(username: String, password: String)
    case oauth(authorizer: @Sendable () -> any HTTPClientAuthorizer)

    static func clientCredentials(
        clientID: String,
        clientSecret: String,
        tokenEndpoint: URL? = nil,
        scopes: [String] = []
    ) -> MCPHTTPAuthorization {
        .oauth {
            let configuration = OAuthConfiguration(
                grantType: .clientCredentials,
                authentication: .clientSecretBasic(
                    clientID: clientID,
                    clientSecret: clientSecret
                ),
                endpointOverrides: .init(tokenEndpoint: tokenEndpoint),
                additionalTokenRequestParameters: scopes.isEmpty
                    ? [:]
                    : ["scope": scopes.joined(separator: " ")]
            )
            return OAuthAuthorizer(configuration: configuration)
        }
    }

    func makeAuthorizer() -> (any HTTPClientAuthorizer)? {
        guard case .oauth(let factory) = self else {
            return nil
        }
        return factory()
    }

    func staticAuthorizationHeader() -> String? {
        switch self {
        case .none, .oauth:
            return nil
        case .bearer(let token):
            return "Bearer \(token)"
        case .basic(let username, let password):
            let credentials = Data("\(username):\(password)".utf8).base64EncodedString()
            return "Basic \(credentials)"
        }
    }

    func validate(server: String) throws {
        switch self {
        case .none, .oauth:
            return
        case .bearer(let token):
            try MCPHTTPHeaderPolicy.validateAuthorizationValue(
                token,
                server: server
            )
        case .basic(let username, let password):
            guard !username.contains(":"), !username.isEmpty, !password.isEmpty else {
                throw MCPConfigurationError.invalidAuthorizationValue(
                    server: server
                )
            }
            try MCPHTTPHeaderPolicy.validateAuthorizationValue(
                username,
                server: server
            )
            try MCPHTTPHeaderPolicy.validateAuthorizationValue(
                password,
                server: server
            )
        }
    }
}
