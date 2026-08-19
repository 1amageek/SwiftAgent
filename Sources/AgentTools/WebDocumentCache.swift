import Foundation

actor WebDocumentCache {
    private struct Key: Sendable, Hashable {
        let url: URL
        let policyIdentifier: String
    }

    private struct Entry: Sendable {
        let document: WebDocument
        let expiresAt: Date
        var accessOrder: UInt64
    }

    private let configuration: WebDocumentCacheConfiguration
    private var entries: [Key: Entry] = [:]
    private var totalBodyBytes = 0
    private var accessOrder: UInt64 = 0

    init(configuration: WebDocumentCacheConfiguration) {
        self.configuration = configuration
    }

    func get(_ authorizedURL: AuthorizedWebURL) -> WebDocument? {
        let key = Key(
            url: authorizedURL.url,
            policyIdentifier: authorizedURL.policyIdentifier
        )
        guard configuration.maximumEntries > 0,
              configuration.timeToLive > 0,
              configuration.timeToLive.isFinite,
              var entry = entries[key] else {
            return nil
        }
        guard Date() <= entry.expiresAt else {
            remove(key)
            return nil
        }
        accessOrder &+= 1
        entry.accessOrder = accessOrder
        entries[key] = entry
        return entry.document.markingCached()
    }

    func insert(
        _ document: WebDocument,
        for authorizedURL: AuthorizedWebURL
    ) {
        let key = Key(
            url: authorizedURL.url,
            policyIdentifier: authorizedURL.policyIdentifier
        )
        guard configuration.maximumEntries > 0,
              configuration.maximumTotalBodyBytes > 0,
              configuration.timeToLive > 0,
              configuration.timeToLive.isFinite,
              document.body.count <= configuration.maximumTotalBodyBytes,
              let lifetime = cacheLifetime(for: document.headers) else {
            return
        }
        removeExpired()
        remove(key)
        accessOrder &+= 1
        entries[key] = Entry(
            document: document,
            expiresAt: Date().addingTimeInterval(lifetime),
            accessOrder: accessOrder
        )
        totalBodyBytes += document.body.count
        evictIfNeeded()
    }

    private func removeExpired() {
        let now = Date()
        let expired = entries.compactMap { key, entry in
            now > entry.expiresAt ? key : nil
        }
        for key in expired {
            remove(key)
        }
    }

    private func evictIfNeeded() {
        while entries.count > configuration.maximumEntries
                || totalBodyBytes > configuration.maximumTotalBodyBytes {
            guard let oldest = entries.min(
                by: { $0.value.accessOrder < $1.value.accessOrder }
            )?.key else {
                return
            }
            remove(oldest)
        }
    }

    private func remove(_ key: Key) {
        guard let removed = entries.removeValue(forKey: key) else {
            return
        }
        totalBodyBytes -= removed.document.body.count
    }

    private func cacheLifetime(
        for headers: [String: String]
    ) -> TimeInterval? {
        let pragmaDirectives = headers["pragma"]?
            .split(separator: ",")
            .map {
                $0.trimmingCharacters(in: .whitespacesAndNewlines)
                    .lowercased()
            } ?? []
        guard headers["set-cookie"] == nil,
              headers["expires"] == nil,
              !pragmaDirectives.contains("no-cache"),
              headers["vary"] == nil else {
            return nil
        }
        let directives = headers["cache-control"]?
            .split(separator: ",")
            .map {
                $0.trimmingCharacters(in: .whitespacesAndNewlines)
                    .lowercased()
            } ?? []
        let parsedDirectives = directives.map { directive in
            let components = directive.split(
                separator: "=",
                maxSplits: 1,
                omittingEmptySubsequences: false
            )
            return (
                name: components[0].trimmingCharacters(
                    in: .whitespacesAndNewlines
                ),
                value: components.count == 2
                    ? components[1].trimmingCharacters(
                        in: .whitespacesAndNewlines
                    )
                    : nil
            )
        }
        let prohibitedDirectives: Set<String> = [
            "no-store",
            "no-cache",
            "private",
        ]
        guard !parsedDirectives.contains(where: {
            prohibitedDirectives.contains($0.name)
        }) else {
            return nil
        }
        let age: TimeInterval
        if let ageValue = headers["age"] {
            guard let seconds = Int64(
                ageValue.trimmingCharacters(in: .whitespacesAndNewlines)
            ), seconds >= 0 else {
                return nil
            }
            age = TimeInterval(seconds)
        } else {
            age = 0
        }
        let maxAgeDirectives = parsedDirectives.filter {
            $0.name == "max-age"
        }
        guard !maxAgeDirectives.isEmpty else {
            let remaining = configuration.timeToLive - age
            return remaining > 0 ? remaining : nil
        }
        var maximumAge = Int64.max
        for directive in maxAgeDirectives {
            guard let rawValue = directive.value else {
                return nil
            }
            let value = rawValue.trimmingCharacters(
                in: CharacterSet(charactersIn: "\"")
            )
            guard let seconds = Int64(value), seconds >= 0 else {
                return nil
            }
            maximumAge = Swift.min(maximumAge, seconds)
        }
        let remaining = Swift.min(
            configuration.timeToLive,
            TimeInterval(maximumAge)
        ) - age
        return remaining > 0 ? remaining : nil
    }
}
