import Foundation
import OpenFoundationModels
import SwiftAgent
import Synchronization
#if canImport(Darwin)
import Darwin
#else
import Glibc
#endif

/// A tool for fetching content from URLs and processing it.
///
/// `URLFetchTool` performs HTTP GET requests to retrieve data from web resources
/// with built-in SSRF protection, HTML to Markdown conversion, and caching.
///
/// ## Features
/// - Fetch content from HTTP/HTTPS URLs
/// - SSRF protection (blocks private IPs, localhost, cloud metadata endpoints)
/// - HTML to Markdown conversion for web pages
/// - Automatic size limits (5MB)
/// - Configurable timeout (30 seconds)
/// - Redirect control (maximum 5 redirects)
/// - Self-cleaning 15-minute cache
///
/// ## Usage
/// - Provide a URL and optional prompt describing what information to extract
/// - HTTP URLs are automatically upgraded to HTTPS
/// - HTML content is converted to Markdown for easier processing
/// - Results may be summarized if content is very large
///
/// ## Limitations
/// - Only supports HTTP and HTTPS URLs
/// - Blocks access to private IP ranges and localhost
/// - Maximum response size: 5MB
/// - Maximum execution time: 30 seconds
/// - Read-only (GET requests only)
public struct URLFetchTool: OpenFoundationModels.Tool {
    public typealias Arguments = FetchInput
    public typealias Output = URLFetchOutput

    public static let name = "url_fetch"
    public var name: String { Self.name }

    public static let description = """
    Fetch URL content. Converts HTML to Markdown. SSRF protection enabled. \
    Max 5MB, 30s timeout. HTTP auto-upgraded to HTTPS.
    """

    public var description: String { Self.description }

    public var parameters: GenerationSchema {
        FetchInput.generationSchema
    }

    // Security configuration
    private let maxResponseSize: Int64 = 5 * 1024 * 1024  // 5MB
    private let timeoutSeconds: TimeInterval = 30
    private let maxRedirects = 5

    // Cache for responses (15 minute TTL)
    private static let cache = URLFetchCache()

    public init() {}
    
    public func call(arguments: FetchInput) async throws -> URLFetchOutput {
        // Upgrade HTTP to HTTPS
        var urlString = arguments.url
        if urlString.hasPrefix("http://") {
            urlString = "https://" + urlString.dropFirst(7)
        }

        guard let url = URL(string: urlString) else {
            return URLFetchOutput(
                success: false,
                output: "Invalid URL: \(arguments.url)",
                metadata: ["error": "Invalid URL"],
                prompt: arguments.prompt
            )
        }

        guard url.scheme == "http" || url.scheme == "https" else {
            return URLFetchOutput(
                success: false,
                output: "Unsupported URL scheme: \(url.scheme ?? "nil")",
                metadata: ["error": "Unsupported URL scheme"],
                prompt: arguments.prompt
            )
        }

        // Check cache first
        if let cached = await Self.cache.get(url: urlString) {
            return URLFetchOutput(
                success: true,
                output: cached.content,
                metadata: [
                    "status": "200",
                    "url": urlString,
                    "cached": "true",
                    "content_type": cached.contentType
                ],
                prompt: arguments.prompt
            )
        }

        // SSRF Protection: Resolve hostname and check for private IPs
        guard let host = url.host else {
            return URLFetchOutput(
                success: false,
                output: "Invalid URL: missing host",
                metadata: ["error": "Missing host"],
                prompt: arguments.prompt
            )
        }

        // Check if host is a blocked pattern
        if isBlockedHost(host) {
            return URLFetchOutput(
                success: false,
                output: "Access denied: localhost and local network addresses are not allowed",
                metadata: [
                    "error": "Blocked host",
                    "host": host
                ],
                prompt: arguments.prompt
            )
        }

        // Resolve DNS to check actual IP addresses
        let resolvedIPs = try await resolveHost(host)
        for ip in resolvedIPs {
            if isPrivateIP(ip) {
                return URLFetchOutput(
                    success: false,
                    output: "Access denied: URL resolves to a private IP address",
                    metadata: [
                        "error": "Private IP detected",
                        "host": host,
                        "resolved_ip": ip
                    ],
                    prompt: arguments.prompt
                )
            }
        }

        // Create custom URLSession with security settings
        let configuration = URLSessionConfiguration.ephemeral
        configuration.timeoutIntervalForRequest = timeoutSeconds
        configuration.timeoutIntervalForResource = timeoutSeconds
        configuration.httpMaximumConnectionsPerHost = 1
        configuration.httpShouldUsePipelining = false
        configuration.waitsForConnectivity = false

        // Create custom delegate for redirect handling
        let delegate = RedirectController(maxRedirects: maxRedirects, ssrfChecker: self)
        let session = URLSession(configuration: configuration, delegate: delegate, delegateQueue: nil)
        defer { session.finishTasksAndInvalidate() }

        do {
            let startTime = Date()
            let (data, response) = try await session.data(from: url)
            let fetchTime = Date().timeIntervalSince(startTime)

            guard let httpResponse = response as? HTTPURLResponse else {
                return URLFetchOutput(
                    success: false,
                    output: "Invalid response type",
                    metadata: ["error": "Invalid response type"],
                    prompt: arguments.prompt
                )
            }

            // Check response size
            let dataSize = Int64(data.count)
            if dataSize > maxResponseSize {
                return URLFetchOutput(
                    success: false,
                    output: "Response too large: \(dataSize) bytes (limit: \(maxResponseSize) bytes)",
                    metadata: [
                        "error": "Response size exceeded",
                        "size": String(dataSize),
                        "limit": String(maxResponseSize)
                    ],
                    prompt: arguments.prompt
                )
            }

            var outputText = String(data: data, encoding: .utf8) ?? "<Non-UTF8 data>"
            let statusCode = httpResponse.statusCode
            let finalURL = httpResponse.url?.absoluteString ?? url.absoluteString

            // Get content type
            let contentType = httpResponse.value(forHTTPHeaderField: "Content-Type") ?? "unknown"

            // Convert HTML to Markdown if content type is HTML
            let isHTML = contentType.lowercased().contains("text/html")
            if isHTML {
                outputText = HTMLToMarkdown.convert(outputText)
            }

            if (200..<300).contains(statusCode) {
                // Cache the result
                await Self.cache.set(url: urlString, content: outputText, contentType: contentType)

                return URLFetchOutput(
                    success: true,
                    output: outputText,
                    metadata: [
                        "status": String(statusCode),
                        "url": arguments.url,
                        "final_url": finalURL,
                        "content_type": contentType,
                        "content_length": String(dataSize),
                        "fetch_time": String(format: "%.3f", fetchTime),
                        "redirects": String(delegate.redirectCount),
                        "converted_to_markdown": String(isHTML)
                    ],
                    prompt: arguments.prompt
                )
            } else {
                return URLFetchOutput(
                    success: false,
                    output: outputText,
                    metadata: [
                        "status": String(statusCode),
                        "url": arguments.url,
                        "final_url": finalURL,
                        "error": "HTTP error \(statusCode)",
                        "content_type": contentType,
                        "content_length": String(dataSize)
                    ],
                    prompt: arguments.prompt
                )
            }
        } catch {
            return URLFetchOutput(
                success: false,
                output: error.localizedDescription,
                metadata: [
                    "url": arguments.url,
                    "error": error.localizedDescription
                ],
                prompt: arguments.prompt
            )
        }
    }
}

/// Input structure for URL fetching operations.
@Generable
public struct FetchInput: Sendable {
    @Guide(description: "The URL to fetch content from (must be fully-formed valid URL)")
    public let url: String

    @Guide(description: "Optional prompt describing what information you want to extract from the page")
    public let prompt: String
}

/// Output structure for URL fetch operations.
public struct URLFetchOutput: Sendable {
    /// Whether the fetch was successful.
    public let success: Bool

    /// The fetched content or error message.
    public let output: String

    /// Additional metadata about the operation.
    public let metadata: [String: String]

    /// The prompt used to process the content.
    public let prompt: String

    public init(success: Bool, output: String, metadata: [String: String], prompt: String = "") {
        self.success = success
        self.output = output
        self.metadata = metadata
        self.prompt = prompt
    }
}

extension URLFetchOutput: PromptRepresentable {
    public var promptRepresentation: Prompt {
        Prompt(description)
    }
}

extension URLFetchOutput: CustomStringConvertible {
    public var description: String {
        let status = success ? "Success" : "Failed"
        let promptInfo = prompt.isEmpty ? "" : "\nPrompt: \(prompt)"
        let metadataString = metadata.isEmpty ? "" : "\nMetadata:\n" + metadata.map { "  \($0.key): \($0.value)" }.joined(separator: "\n")

        return """
        WebFetch [\(status)]\(promptInfo)
        \(output)\(metadataString)
        """
    }
}

// MARK: - URL Fetch Cache

/// A simple cache for URL fetch results with 15-minute TTL.
actor URLFetchCache {
    struct CacheEntry {
        let content: String
        let contentType: String
        let timestamp: Date
    }

    private var cache: [String: CacheEntry] = [:]
    private let ttl: TimeInterval = 15 * 60  // 15 minutes

    func get(url: String) -> CacheEntry? {
        guard let entry = cache[url] else { return nil }

        // Check if entry has expired
        if Date().timeIntervalSince(entry.timestamp) > ttl {
            cache.removeValue(forKey: url)
            return nil
        }

        return entry
    }

    func set(url: String, content: String, contentType: String) {
        // Clean expired entries periodically
        cleanExpired()

        cache[url] = CacheEntry(
            content: content,
            contentType: contentType,
            timestamp: Date()
        )
    }

    private func cleanExpired() {
        let now = Date()
        cache = cache.filter { now.timeIntervalSince($0.value.timestamp) <= ttl }
    }
}

// MARK: - HTML to Markdown Converter

/// A simple HTML to Markdown converter.
enum HTMLToMarkdown {
    /// Converts HTML content to Markdown format.
    static func convert(_ html: String) -> String {
        var result = html

        // Remove script and style tags and their content
        result = removeTag(result, tag: "script")
        result = removeTag(result, tag: "style")
        result = removeTag(result, tag: "noscript")
        result = removeTag(result, tag: "head")
        result = removeTag(result, tag: "nav")
        result = removeTag(result, tag: "footer")

        // Convert headers
        result = replacePattern(result, pattern: "<h1[^>]*>(.*?)</h1>", replacement: "# $1\n\n")
        result = replacePattern(result, pattern: "<h2[^>]*>(.*?)</h2>", replacement: "## $1\n\n")
        result = replacePattern(result, pattern: "<h3[^>]*>(.*?)</h3>", replacement: "### $1\n\n")
        result = replacePattern(result, pattern: "<h4[^>]*>(.*?)</h4>", replacement: "#### $1\n\n")
        result = replacePattern(result, pattern: "<h5[^>]*>(.*?)</h5>", replacement: "##### $1\n\n")
        result = replacePattern(result, pattern: "<h6[^>]*>(.*?)</h6>", replacement: "###### $1\n\n")

        // Convert paragraphs
        result = replacePattern(result, pattern: "<p[^>]*>(.*?)</p>", replacement: "$1\n\n")

        // Convert line breaks
        result = result.replacingOccurrences(of: "<br>", with: "\n")
        result = result.replacingOccurrences(of: "<br/>", with: "\n")
        result = result.replacingOccurrences(of: "<br />", with: "\n")

        // Convert bold
        result = replacePattern(result, pattern: "<strong[^>]*>(.*?)</strong>", replacement: "**$1**")
        result = replacePattern(result, pattern: "<b[^>]*>(.*?)</b>", replacement: "**$1**")

        // Convert italic
        result = replacePattern(result, pattern: "<em[^>]*>(.*?)</em>", replacement: "*$1*")
        result = replacePattern(result, pattern: "<i[^>]*>(.*?)</i>", replacement: "*$1*")

        // Convert code
        result = replacePattern(result, pattern: "<code[^>]*>(.*?)</code>", replacement: "`$1`")
        result = replacePattern(result, pattern: "<pre[^>]*>(.*?)</pre>", replacement: "```\n$1\n```\n\n")

        // Convert links
        result = replacePattern(result, pattern: "<a[^>]*href=\"([^\"]+)\"[^>]*>(.*?)</a>", replacement: "[$2]($1)")

        // Convert lists
        result = replacePattern(result, pattern: "<li[^>]*>(.*?)</li>", replacement: "- $1\n")
        result = replacePattern(result, pattern: "<ul[^>]*>", replacement: "\n")
        result = replacePattern(result, pattern: "</ul>", replacement: "\n")
        result = replacePattern(result, pattern: "<ol[^>]*>", replacement: "\n")
        result = replacePattern(result, pattern: "</ol>", replacement: "\n")

        // Convert blockquotes
        result = replacePattern(result, pattern: "<blockquote[^>]*>(.*?)</blockquote>", replacement: "> $1\n\n")

        // Convert divs and spans (just extract content)
        result = replacePattern(result, pattern: "<div[^>]*>(.*?)</div>", replacement: "$1\n")
        result = replacePattern(result, pattern: "<span[^>]*>(.*?)</span>", replacement: "$1")

        // Remove remaining HTML tags
        result = replacePattern(result, pattern: "<[^>]+>", replacement: "")

        // Decode HTML entities
        result = decodeHTMLEntities(result)

        // Clean up whitespace
        result = cleanWhitespace(result)

        return result
    }

    private static func removeTag(_ html: String, tag: String) -> String {
        let pattern = "<\(tag)[^>]*>.*?</\(tag)>"
        return replacePattern(html, pattern: pattern, replacement: "", options: [.caseInsensitive, .dotMatchesLineSeparators])
    }

    private static func replacePattern(
        _ string: String,
        pattern: String,
        replacement: String,
        options: NSRegularExpression.Options = [.caseInsensitive, .dotMatchesLineSeparators]
    ) -> String {
        guard let regex = try? NSRegularExpression(pattern: pattern, options: options) else {
            return string
        }

        let range = NSRange(string.startIndex..., in: string)
        return regex.stringByReplacingMatches(in: string, options: [], range: range, withTemplate: replacement)
    }

    private static func decodeHTMLEntities(_ string: String) -> String {
        var result = string
        let entities: [(String, String)] = [
            ("&nbsp;", " "),
            ("&amp;", "&"),
            ("&lt;", "<"),
            ("&gt;", ">"),
            ("&quot;", "\""),
            ("&apos;", "'"),
            ("&#39;", "'"),
            ("&mdash;", "—"),
            ("&ndash;", "–"),
            ("&hellip;", "…"),
            ("&copy;", "©"),
            ("&reg;", "®"),
            ("&trade;", "™")
        ]

        for (entity, char) in entities {
            result = result.replacingOccurrences(of: entity, with: char)
        }

        // Handle numeric entities
        result = replacePattern(result, pattern: "&#(\\d+);", replacement: "") // Simplified - just remove

        return result
    }

    private static func cleanWhitespace(_ string: String) -> String {
        var result = string

        // Replace multiple newlines with double newlines
        result = replacePattern(result, pattern: "\n{3,}", replacement: "\n\n", options: [])

        // Replace multiple spaces with single space
        result = replacePattern(result, pattern: " {2,}", replacement: " ", options: [])

        // Trim whitespace from each line
        result = result.components(separatedBy: .newlines)
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .joined(separator: "\n")

        // Trim overall
        result = result.trimmingCharacters(in: .whitespacesAndNewlines)

        return result
    }
}

// MARK: - SSRF Protection

extension URLFetchTool {
    /// Check if a host is blocked (localhost, etc.)
    func isBlockedHost(_ host: String) -> Bool {
        let lowercaseHost = host.lowercased()
        let blockedPatterns = [
            "localhost",
            "127.0.0.1",
            "::1",
            "0.0.0.0",
            "::",
            "169.254.169.254",  // AWS metadata endpoint
            "metadata.google.internal",  // GCP metadata
            "metadata.azure.com"  // Azure metadata
        ]
        
        for pattern in blockedPatterns {
            if lowercaseHost == pattern || lowercaseHost.hasPrefix(pattern + ":") {
                return true
            }
        }
        
        // Check if it's already an IP address that's private
        if isIPAddress(host) && isPrivateIP(host) {
            return true
        }
        
        return false
    }
    
    /// Check if a string is an IP address
    func isIPAddress(_ string: String) -> Bool {
        // Check IPv4
        let ipv4Pattern = #"^\d{1,3}\.\d{1,3}\.\d{1,3}\.\d{1,3}$"#
        if string.range(of: ipv4Pattern, options: .regularExpression) != nil {
            return true
        }
        
        // Check IPv6 (simplified check)
        if string.contains(":") && (string.contains("::") || string.filter { $0 == ":" }.count >= 2) {
            return true
        }
        
        return false
    }
    
    /// Check if an IP address is in a private range
    func isPrivateIP(_ ip: String) -> Bool {
        // IPv4 private ranges
        if ip.hasPrefix("10.") ||
           ip.hasPrefix("172.") ||
           ip.hasPrefix("192.168.") ||
           ip.hasPrefix("169.254.") ||  // Link-local
           ip.hasPrefix("127.") ||      // Loopback
           ip == "0.0.0.0" {
            
            // For 172.x.x.x, check if it's in the 172.16.0.0/12 range
            if ip.hasPrefix("172.") {
                let components = ip.split(separator: ".").compactMap { Int($0) }
                if components.count >= 2 {
                    let secondOctet = components[1]
                    return secondOctet >= 16 && secondOctet <= 31
                }
            }
            return true
        }
        
        // IPv6 private ranges
        let ipv6PrivatePrefixes = [
            "fc",   // Unique local
            "fd",   // Unique local
            "fe80", // Link-local
            "::1",  // Loopback
            "::"    // Unspecified
        ]
        
        let lowercaseIP = ip.lowercased()
        for prefix in ipv6PrivatePrefixes {
            if lowercaseIP.hasPrefix(prefix) {
                return true
            }
        }
        
        return false
    }
    
    /// Resolve a hostname to IP addresses
    func resolveHost(_ host: String) async throws -> [String] {
        // If it's already an IP address, return it
        if isIPAddress(host) {
            return [host]
        }
        
        // Perform DNS resolution
        return try await withCheckedThrowingContinuation { continuation in
            DispatchQueue.global().async {
                var hints = addrinfo()
                hints.ai_family = AF_UNSPEC  // Both IPv4 and IPv6
                hints.ai_socktype = SOCK_STREAM
                
                var result: UnsafeMutablePointer<addrinfo>?
                let status = getaddrinfo(host, nil, &hints, &result)
                
                guard status == 0, let addrList = result else {
                    continuation.resume(throwing: FileSystemError.operationFailed(
                        reason: "DNS resolution failed for host: \(host)"
                    ))
                    return
                }
                
                defer { freeaddrinfo(addrList) }
                
                var ips: [String] = []
                var current: UnsafeMutablePointer<addrinfo>? = addrList
                
                while let addr = current {
                    if addr.pointee.ai_family == AF_INET {
                        // IPv4
                        var hostname = [CChar](repeating: 0, count: Int(NI_MAXHOST))
                        let result = getnameinfo(
                            addr.pointee.ai_addr,
                            addr.pointee.ai_addrlen,
                            &hostname,
                            socklen_t(hostname.count),
                            nil,
                            0,
                            NI_NUMERICHOST
                        )
                        
                        if result == 0 {
                            // Properly handle C string to Swift String conversion
                            let hostnameString = hostname.withUnsafeBufferPointer { buffer in
                                // Find null terminator
                                let length = buffer.firstIndex(of: 0) ?? buffer.count
                                // Convert CChar (Int8) buffer to UInt8 for UTF8 decoding
                                let bytes = buffer.prefix(length).map { UInt8(bitPattern: $0) }
                                return String(decoding: bytes, as: UTF8.self)
                            }
                            ips.append(hostnameString)
                        }
                    } else if addr.pointee.ai_family == AF_INET6 {
                        // IPv6
                        var hostname = [CChar](repeating: 0, count: Int(NI_MAXHOST))
                        let result = getnameinfo(
                            addr.pointee.ai_addr,
                            addr.pointee.ai_addrlen,
                            &hostname,
                            socklen_t(hostname.count),
                            nil,
                            0,
                            NI_NUMERICHOST
                        )
                        
                        if result == 0 {
                            // Properly handle C string to Swift String conversion
                            let hostnameString = hostname.withUnsafeBufferPointer { buffer in
                                // Find null terminator
                                let length = buffer.firstIndex(of: 0) ?? buffer.count
                                // Convert CChar (Int8) buffer to UInt8 for UTF8 decoding
                                let bytes = buffer.prefix(length).map { UInt8(bitPattern: $0) }
                                return String(decoding: bytes, as: UTF8.self)
                            }
                            ips.append(hostnameString)
                        }
                    }
                    
                    current = addr.pointee.ai_next
                }
                
                if ips.isEmpty {
                    continuation.resume(throwing: FileSystemError.operationFailed(
                        reason: "No IP addresses found for host: \(host)"
                    ))
                } else {
                    continuation.resume(returning: ips)
                }
            }
        }
    }
}

// MARK: - Redirect Controller

private final class RedirectController: NSObject, URLSessionTaskDelegate, Sendable {
    let maxRedirects: Int
    let ssrfChecker: URLFetchTool
    private let _redirectCount = Mutex<Int>(0)

    var redirectCount: Int {
        _redirectCount.withLock { $0 }
    }

    init(maxRedirects: Int, ssrfChecker: URLFetchTool) {
        self.maxRedirects = maxRedirects
        self.ssrfChecker = ssrfChecker
        super.init()
    }

    func urlSession(
        _ session: URLSession,
        task: URLSessionTask,
        willPerformHTTPRedirection response: HTTPURLResponse,
        newRequest request: URLRequest,
        completionHandler: @escaping @Sendable (URLRequest?) -> Void
    ) {
        guard let newURL = request.url else {
            completionHandler(nil)
            return
        }

        // Check redirect count
        let currentCount = _redirectCount.withLock { count in
            count += 1
            return count
        }
        
        if currentCount > maxRedirects {
            completionHandler(nil)
            return
        }
        
        // Check if new URL is safe
        guard let host = newURL.host else {
            completionHandler(nil)
            return
        }
        
        // Block redirects to private IPs or localhost
        if ssrfChecker.isBlockedHost(host) {
            completionHandler(nil)
            return
        }
        
        // For non-blocked hosts, still need to check resolved IPs
        Task {
            do {
                let resolvedIPs = try await ssrfChecker.resolveHost(host)
                for ip in resolvedIPs {
                    if ssrfChecker.isPrivateIP(ip) {
                        completionHandler(nil)
                        return
                    }
                }
                // Safe to redirect
                completionHandler(request)
            } catch {
                // DNS resolution failed, block redirect
                completionHandler(nil)
            }
        }
    }
}
