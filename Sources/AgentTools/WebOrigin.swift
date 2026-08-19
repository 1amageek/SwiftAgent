import Foundation

public struct WebOrigin: Sendable, Hashable, CustomStringConvertible {
    public let scheme: String
    public let host: String
    public let port: Int

    public init(scheme: String, host: String, port: Int? = nil) throws {
        let normalizedScheme = scheme.lowercased()
        guard normalizedScheme == "https" || normalizedScheme == "http" else {
            throw WebHTTPError.unsupportedScheme(scheme)
        }
        let normalizedHost = Self.normalize(host)
        guard !normalizedHost.isEmpty else {
            throw WebHTTPError.invalidURL(host)
        }
        if normalizedScheme == "http",
           !Self.isLoopback(normalizedHost) {
            throw WebHTTPError.insecureOrigin("http://\(normalizedHost)")
        }
        let effectivePort = port ?? (normalizedScheme == "https" ? 443 : 80)
        guard (1...65_535).contains(effectivePort) else {
            throw WebHTTPError.invalidURL("\(host):\(effectivePort)")
        }
        self.scheme = normalizedScheme
        self.host = normalizedHost
        self.port = effectivePort
    }

    public init(url: URL) throws {
        guard let scheme = url.scheme, let host = url.host else {
            throw WebHTTPError.invalidURL(url.absoluteString)
        }
        try self.init(scheme: scheme, host: host, port: url.port)
    }

    public var description: String {
        let defaultPort = scheme == "https" ? 443 : 80
        let renderedHost = host.contains(":") ? "[\(host)]" : host
        return port == defaultPort
            ? "\(scheme)://\(renderedHost)"
            : "\(scheme)://\(renderedHost):\(port)"
    }

    static func normalize(_ host: String) -> String {
        var normalized = host.lowercased()
        if normalized.hasPrefix("[") && normalized.hasSuffix("]") {
            normalized.removeFirst()
            normalized.removeLast()
        }
        while normalized.last == "." {
            normalized.removeLast()
        }
        return normalized
    }

    private static func isLoopback(_ host: String) -> Bool {
        host == "localhost" || host == "127.0.0.1" || host == "::1"
    }
}
