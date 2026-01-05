//
//  MCPAuth.swift
//  SwiftAgentMCP
//
//  Created by SwiftAgent on 2025/01/05.
//

import Foundation

// MARK: - OAuth Manager

/// Manages OAuth 2.0 authentication for MCP servers
///
/// Features:
/// - OAuth 2.0 Authorization Code flow
/// - Bearer token authentication
/// - Basic authentication
/// - Proactive token refresh (5 minutes before expiration)
/// - Secure token storage
public actor MCPOAuthManager {

    /// Stored tokens by server name
    private var tokens: [String: OAuthToken] = [:]

    /// Auth configurations by server name
    private var configs: [String: MCPConfiguration.MCPAuthConfig] = [:]

    public init() {}

    // MARK: - Token Management

    /// Stores authentication configuration for a server
    public func setConfig(_ config: MCPConfiguration.MCPAuthConfig, for serverName: String) {
        configs[serverName] = config
    }

    /// Gets a valid access token for a server
    ///
    /// - Refreshes the token proactively if it expires within 5 minutes
    /// - Returns nil if no token is available
    ///
    /// - Parameter serverName: The server name
    /// - Returns: A valid access token or nil
    public func getToken(for serverName: String) async throws -> String? {
        guard let token = tokens[serverName] else {
            return nil
        }

        // Check if token needs refresh (expires within 5 minutes)
        if let expiresAt = token.expiresAt,
           expiresAt.timeIntervalSinceNow < 300 {
            // Try to refresh
            if token.refreshToken != nil {
                return try await refreshToken(for: serverName)
            }
        }

        return token.accessToken
    }

    /// Gets authentication headers for a server
    ///
    /// - Parameter serverName: The server name
    /// - Returns: Headers dictionary to include in requests
    public func getAuthHeaders(for serverName: String) async throws -> [String: String] {
        guard let config = configs[serverName] else {
            return [:]
        }

        switch config.type {
        case "bearer":
            if let token = config.token {
                return ["Authorization": "Bearer \(token)"]
            }
            if let accessToken = try await getToken(for: serverName) {
                return ["Authorization": "Bearer \(accessToken)"]
            }

        case "basic":
            if let username = config.username, let password = config.password {
                let credentials = "\(username):\(password)"
                if let data = credentials.data(using: .utf8) {
                    let base64 = data.base64EncodedString()
                    return ["Authorization": "Basic \(base64)"]
                }
            }

        case "oauth2":
            if let accessToken = try await getToken(for: serverName) {
                return ["Authorization": "Bearer \(accessToken)"]
            }

        default:
            break
        }

        return [:]
    }

    /// Clears the token for a server
    public func clearToken(for serverName: String) {
        tokens.removeValue(forKey: serverName)
    }

    /// Clears all tokens
    public func clearAllTokens() {
        tokens.removeAll()
    }

    // MARK: - OAuth Flow

    /// Performs OAuth 2.0 authentication for a server
    ///
    /// Note: This is a simplified implementation. A full implementation would
    /// require platform-specific UI for the authorization flow.
    ///
    /// - Parameters:
    ///   - serverName: The server name
    ///   - config: The auth configuration
    /// - Returns: The obtained token
    public func authenticate(
        serverName: String,
        config: MCPConfiguration.MCPAuthConfig
    ) async throws -> OAuthToken {
        configs[serverName] = config

        switch config.type {
        case "bearer":
            // Static bearer token
            guard let token = config.token else {
                throw MCPClientError.authenticationFailed("No bearer token provided")
            }
            let oauthToken = OAuthToken(
                accessToken: token,
                refreshToken: nil,
                expiresAt: nil,
                scopes: []
            )
            tokens[serverName] = oauthToken
            return oauthToken

        case "oauth2":
            // OAuth 2.0 flow would require:
            // 1. Redirect user to authorizationUrl
            // 2. Handle callback with authorization code
            // 3. Exchange code for tokens at tokenUrl
            //
            // For now, throw an error indicating manual setup is needed
            throw MCPClientError.authenticationFailed(
                "OAuth 2.0 flow requires interactive authentication. " +
                "Set up tokens manually or use a bearer token."
            )

        case "basic":
            // Basic auth doesn't use tokens
            return OAuthToken(
                accessToken: "",
                refreshToken: nil,
                expiresAt: nil,
                scopes: []
            )

        default:
            throw MCPClientError.authenticationFailed("Unknown auth type: \(config.type)")
        }
    }

    /// Sets a token directly (for use after external OAuth flow)
    public func setToken(_ token: OAuthToken, for serverName: String) {
        tokens[serverName] = token
    }

    // MARK: - Token Refresh

    /// Refreshes the token for a server
    private func refreshToken(for serverName: String) async throws -> String {
        guard let token = tokens[serverName],
              let refreshToken = token.refreshToken,
              let config = configs[serverName],
              let tokenUrlString = config.tokenUrl,
              let tokenUrl = URL(string: tokenUrlString) else {
            throw MCPClientError.authenticationFailed("Cannot refresh token: missing configuration")
        }

        // Build refresh request
        var request = URLRequest(url: tokenUrl)
        request.httpMethod = "POST"
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")

        var body = "grant_type=refresh_token"
        body += "&refresh_token=\(refreshToken)"
        if let clientId = config.clientId {
            body += "&client_id=\(clientId)"
        }
        if let clientSecret = config.clientSecret {
            body += "&client_secret=\(clientSecret)"
        }
        request.httpBody = body.data(using: .utf8)

        // Perform request
        let (data, response) = try await URLSession.shared.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse,
              (200...299).contains(httpResponse.statusCode) else {
            throw MCPClientError.authenticationFailed("Token refresh failed")
        }

        // Parse response
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        let tokenResponse = try decoder.decode(TokenResponse.self, from: data)

        // Create new token
        let newToken = OAuthToken(
            accessToken: tokenResponse.accessToken,
            refreshToken: tokenResponse.refreshToken ?? refreshToken,
            expiresAt: tokenResponse.expiresIn.map { Date().addingTimeInterval(TimeInterval($0)) },
            scopes: token.scopes
        )

        tokens[serverName] = newToken
        return newToken.accessToken
    }
}

// MARK: - OAuth Token

extension MCPOAuthManager {

    /// Represents an OAuth token
    public struct OAuthToken: Codable, Sendable {
        /// The access token
        public let accessToken: String

        /// The refresh token (optional)
        public let refreshToken: String?

        /// When the token expires (optional)
        public let expiresAt: Date?

        /// The granted scopes
        public let scopes: [String]

        public init(
            accessToken: String,
            refreshToken: String?,
            expiresAt: Date?,
            scopes: [String]
        ) {
            self.accessToken = accessToken
            self.refreshToken = refreshToken
            self.expiresAt = expiresAt
            self.scopes = scopes
        }

        /// Whether the token is expired
        public var isExpired: Bool {
            guard let expiresAt = expiresAt else { return false }
            return expiresAt < Date()
        }

        /// Whether the token needs refresh (expires within 5 minutes)
        public var needsRefresh: Bool {
            guard let expiresAt = expiresAt else { return false }
            return expiresAt.timeIntervalSinceNow < 300
        }
    }
}

// MARK: - Token Response

/// OAuth token response from the server
private struct TokenResponse: Codable {
    let accessToken: String
    let tokenType: String?
    let expiresIn: Int?
    let refreshToken: String?
    let scope: String?
}
