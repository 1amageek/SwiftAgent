import Foundation

public enum WebHTTPError: Error, LocalizedError, Sendable {
    case invalidURL(String)
    case unsupportedScheme(String)
    case insecureOrigin(String)
    case userInformationNotAllowed
    case originNotAuthorized(String)
    case invalidRequestHeader(String)
    case prohibitedRequestHeader(String)
    case invalidTimeout
    case invalidBodyLimit(Int)
    case invalidRedirectLimit(Int)
    case invalidCacheConfiguration(String)
    case deadlineExceeded
    case invalidResponse
    case responseTooLarge(actual: Int64?, maximum: Int)
    case responseURLMismatch(expected: String, actual: String)
    case transport(String)
    case redirectMissingLocation(Int)
    case redirectLimitExceeded(Int)
    case unsupportedTextEncoding(String?)
    case httpStatus(Int)

    public var errorDescription: String? {
        switch self {
        case .invalidURL(let value):
            return "Invalid web URL: \(value)"
        case .unsupportedScheme(let scheme):
            return "Unsupported web URL scheme: \(scheme)"
        case .insecureOrigin(let origin):
            return "Trusted web origins require HTTPS or loopback HTTP: \(origin)"
        case .userInformationNotAllowed:
            return "User information is not allowed in web URLs"
        case .originNotAuthorized(let origin):
            return "Web origin is not authorized: \(origin)"
        case .invalidRequestHeader(let name):
            return "Invalid web request header: \(name)"
        case .prohibitedRequestHeader(let name):
            return "Web request header is controlled by the HTTP adapter: \(name)"
        case .invalidTimeout:
            return "Web request timeout must be finite and greater than zero"
        case .invalidBodyLimit(let limit):
            return "Web response body limit must be greater than zero: \(limit)"
        case .invalidRedirectLimit(let limit):
            return "Web redirect limit must not be negative: \(limit)"
        case .invalidCacheConfiguration(let reason):
            return "Invalid web cache configuration: \(reason)"
        case .deadlineExceeded:
            return "Web request deadline exceeded"
        case .invalidResponse:
            return "Web client received a non-HTTP or incomplete response"
        case .responseTooLarge(let actual, let maximum):
            if let actual {
                return "Web response size \(actual) exceeds maximum \(maximum)"
            }
            return "Web response exceeded maximum size \(maximum)"
        case .responseURLMismatch(let expected, let actual):
            return "Web client returned URL '\(actual)' for request '\(expected)'"
        case .transport(let reason):
            return "Web transport failed: \(reason)"
        case .redirectMissingLocation(let status):
            return "HTTP redirect \(status) did not include a Location header"
        case .redirectLimitExceeded(let maximum):
            return "Web request exceeded redirect limit \(maximum)"
        case .unsupportedTextEncoding(let contentType):
            return "Web response is not UTF-8 text (Content-Type: \(contentType ?? "unknown"))"
        case .httpStatus(let status):
            return "Web request failed with HTTP status \(status)"
        }
    }
}
