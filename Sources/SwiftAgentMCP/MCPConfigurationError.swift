import Foundation

public enum MCPConfigurationError: Error, LocalizedError, Sendable {
    case emptyServerName
    case invalidServerName(String)
    case missingCommand(server: String)
    case missingURL(server: String)
    case conflictingTransportFields(server: String)
    case unsupportedTransport(server: String, value: String)
    case invalidURL(server: String, value: String)
    case insecureEndpoint(server: String, value: String)
    case invalidWorkingDirectory(server: String, value: String)
    case invalidHTTPHeader(server: String, name: String)
    case prohibitedHTTPHeader(server: String, name: String)
    case invalidAuthorizationValue(server: String)
    case authorizationNotSupported(server: String, transport: String)
    case insecureAuthorizationEndpoint(server: String, value: String)
    case unsupportedAuthorization(server: String, value: String)
    case incompleteAuthorization(server: String, value: String)
    case conflictingAuthorizationFields(server: String, value: String)
    case obsoleteConfigurationField(String)
    case unknownConfigurationField(String)
    case missingEnvironmentVariable(String)
    case invalidEnvironmentValue(variable: String, value: String)
    case nonPositiveTimeout(server: String)
    case nonPositivePaginationLimit(server: String)
    case nonPositiveMessageLimit(server: String)

    public var errorDescription: String? {
        switch self {
        case .emptyServerName:
            return "MCP server name must not be empty"
        case .invalidServerName(let name):
            return "MCP server name '\(name)' must contain only ASCII letters, digits, dot, dash, or underscore and fit the 128-byte qualified tool namespace"
        case .missingCommand(let server):
            return "MCP server '\(server)' requires a stdio command"
        case .missingURL(let server):
            return "MCP server '\(server)' requires a Streamable HTTP URL"
        case .conflictingTransportFields(let server):
            return "MCP server '\(server)' mixes stdio and Streamable HTTP fields"
        case .unsupportedTransport(let server, let value):
            return "MCP server '\(server)' uses unsupported transport '\(value)'"
        case .invalidURL(let server, let value):
            return "MCP server '\(server)' has invalid URL '\(value)'"
        case .insecureEndpoint(let server, let value):
            return "MCP server '\(server)' must use HTTPS or loopback HTTP, not '\(value)'"
        case .invalidWorkingDirectory(let server, let value):
            return "MCP server '\(server)' has non-file working directory '\(value)'"
        case .invalidHTTPHeader(let server, let name):
            return "MCP server '\(server)' has invalid HTTP header '\(name)'"
        case .prohibitedHTTPHeader(let server, let name):
            return "MCP server '\(server)' HTTP header '\(name)' is owned by the transport or authorization boundary"
        case .invalidAuthorizationValue(let server):
            return "MCP server '\(server)' has an invalid HTTP authorization value"
        case .authorizationNotSupported(let server, let transport):
            return "MCP server '\(server)' cannot use HTTP authorization with \(transport) transport"
        case .insecureAuthorizationEndpoint(let server, let value):
            return "MCP server '\(server)' OAuth endpoint must use HTTPS or loopback HTTP, not '\(value)'"
        case .unsupportedAuthorization(let server, let value):
            return "MCP server '\(server)' uses unsupported authorization '\(value)'"
        case .incompleteAuthorization(let server, let value):
            return "MCP server '\(server)' has incomplete '\(value)' authorization"
        case .conflictingAuthorizationFields(let server, let value):
            return "MCP server '\(server)' mixes fields that do not belong to '\(value)' authorization"
        case .obsoleteConfigurationField(let field):
            return "MCP configuration field '\(field)' is obsolete and must be replaced with the current explicit fields"
        case .unknownConfigurationField(let field):
            return "MCP configuration contains unknown field '\(field)'"
        case .missingEnvironmentVariable(let variable):
            return "Required environment variable '\(variable)' is not defined"
        case .invalidEnvironmentValue(let variable, let value):
            return "Environment variable '\(variable)' has invalid value '\(value)'"
        case .nonPositiveTimeout(let server):
            return "MCP server '\(server)' timeouts must be positive"
        case .nonPositivePaginationLimit(let server):
            return "MCP server '\(server)' pagination limit must be positive"
        case .nonPositiveMessageLimit(let server):
            return "MCP server '\(server)' message byte limit must be positive"
        }
    }
}
