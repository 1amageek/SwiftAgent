import Foundation

public struct WebDomainFilter: Sendable, Hashable {
    public let allowedDomains: Set<String>
    public let blockedDomains: Set<String>

    public init(
        allowedDomains: [String],
        blockedDomains: [String]
    ) throws {
        self.allowedDomains = try Set(allowedDomains.map(Self.validate))
        self.blockedDomains = try Set(blockedDomains.map(Self.validate))
    }

    public func allows(host: String) -> Bool {
        let host = WebOrigin.normalize(host)
        let isAllowed = allowedDomains.isEmpty
            || allowedDomains.contains(where: { Self.matches(host, domain: $0) })
        let isBlocked = blockedDomains.contains {
            Self.matches(host, domain: $0)
        }
        return isAllowed && !isBlocked
    }

    private static func validate(_ value: String) throws -> String {
        let domain = WebOrigin.normalize(
            value.trimmingCharacters(in: .whitespacesAndNewlines)
        )
        guard !domain.isEmpty, domain.count <= 253 else {
            throw WebSearchError.invalidDomain(value)
        }
        let labels = domain.split(separator: ".", omittingEmptySubsequences: false)
        guard labels.allSatisfy({ label in
            guard !label.isEmpty,
                  label.count <= 63,
                  label.first != "-",
                  label.last != "-" else {
                return false
            }
            return label.utf8.allSatisfy { byte in
                (byte >= 48 && byte <= 57)
                    || (byte >= 97 && byte <= 122)
                    || byte == 45
            }
        }) else {
            throw WebSearchError.invalidDomain(value)
        }
        return domain
    }

    private static func matches(_ host: String, domain: String) -> Bool {
        host == domain || host.hasSuffix(".\(domain)")
    }
}
