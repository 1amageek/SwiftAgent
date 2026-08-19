import Foundation

public enum WebSearchError: Error, LocalizedError, Sendable {
    case emptyQuery
    case queryTooLong(actual: Int, maximum: Int)
    case invalidLimit(Int)
    case invalidDomain(String)
    case invalidDomainList(String)
    case invalidProviderResult(String)
    case providerHTTPStatus(Int)
    case invalidProviderEncoding

    public var errorDescription: String? {
        switch self {
        case .emptyQuery:
            return "Web search query cannot be empty"
        case .queryTooLong(let actual, let maximum):
            return "Web search query length \(actual) exceeds maximum \(maximum)"
        case .invalidLimit(let limit):
            return "Web search result limit is invalid: \(limit)"
        case .invalidDomain(let domain):
            return "Web search domain is invalid: \(domain)"
        case .invalidDomainList(let value):
            return "Web search domain list is invalid JSON: \(value)"
        case .invalidProviderResult(let reason):
            return "Web search provider returned an invalid result: \(reason)"
        case .providerHTTPStatus(let status):
            return "Web search provider returned HTTP status \(status)"
        case .invalidProviderEncoding:
            return "Web search provider returned non-UTF-8 content"
        }
    }
}
