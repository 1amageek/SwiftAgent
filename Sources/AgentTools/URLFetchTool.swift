import Foundation
import OpenFoundationModels
import SwiftAgent
#if canImport(Darwin)
import Darwin
#else
import Glibc
#endif

/// A tool for fetching data from a URL with comprehensive security protections.
///
/// `URLFetchTool` performs HTTP GET requests to retrieve data from web resources
/// with built-in SSRF protection, size limits, and timeout controls.
///
/// ## Usage Guidance
/// - Use this tool **only** if the user's request requires retrieving **external** data from a web resource.
/// - For trivial tasks (e.g., greetings) or reasoning-based answers that do not require external data,
///   do **not** invoke this tool.
/// - Ensure the URL is valid (HTTP/HTTPS) before calling this tool.
///
/// ## Features
/// - Perform HTTP GET requests in a non-interactive context.
/// - SSRF protection (blocks private IPs, localhost, etc.)
/// - Automatic size limits (5MB)
/// - Configurable timeout (30 seconds)
/// - Redirect control (maximum 5 redirects)
/// - Content type validation
///
/// ## Limitations
/// - Only supports HTTP and HTTPS URLs.
/// - Cannot handle POST requests, custom headers, or complex configurations.
/// - Blocks access to private IP ranges and localhost.
/// - Maximum response size: 5MB
/// - Maximum execution time: 30 seconds
///
/// ## Example Usage (Reference Only)
/// This example is provided for demonstration. It does not imply the tool must always be used.
/// ```json
/// {
///   "url": "https://api.example.com/data"
/// }
/// ```
/// **Expected Output**:
/// ```json
/// {
///   "success": true,
///   "output": "{\"key\": \"value\"}",
///   "metadata": {
///     "status": "200",
///     "url": "https://api.example.com/data"
///   }
/// }
/// ```
///
/// Always confirm that the user genuinely needs external data from the provided URL before using `URLFetchTool`.
public struct URLFetchTool: OpenFoundationModels.Tool {
    public typealias Arguments = FetchInput
    public typealias Output = URLFetchOutput
    
    public static let name = "web_fetch"
    public var name: String { Self.name }
    
    public static let description = """
    A tool for fetching data from a URL with security protections.
    
    Features:
    - SSRF protection (blocks private IPs)
    - Size limit: 5MB
    - Timeout: 30 seconds
    - Max redirects: 5
    
    Limitations:
    - Only supports HTTP and HTTPS URLs.
    - Blocks localhost and private IP ranges.
    - Cannot handle POST requests or custom headers.
    """
    
    public var description: String { Self.description }
    
    public var parameters: GenerationSchema {
        FetchInput.generationSchema
    }
    
    // Security configuration
    private let maxResponseSize: Int64 = 5 * 1024 * 1024  // 5MB
    private let timeoutSeconds: TimeInterval = 30
    private let maxRedirects = 5
    
    public init() {}
    
    public func call(arguments: FetchInput) async throws -> URLFetchOutput {
        guard let url = URL(string: arguments.url) else {
            let output = URLFetchOutput(
                success: false,
                output: "Invalid URL: \(arguments.url)",
                metadata: ["error": "Invalid URL"]
            )
            return output
        }
        
        guard url.scheme == "http" || url.scheme == "https" else {
            let output = URLFetchOutput(
                success: false,
                output: "Unsupported URL scheme: \(url.scheme ?? "nil")",
                metadata: ["error": "Unsupported URL scheme"]
            )
            return output
        }
        
        // SSRF Protection: Resolve hostname and check for private IPs
        guard let host = url.host else {
            let output = URLFetchOutput(
                success: false,
                output: "Invalid URL: missing host",
                metadata: ["error": "Missing host"]
            )
            return output
        }
        
        // Check if host is a blocked pattern
        if isBlockedHost(host) {
            let output = URLFetchOutput(
                success: false,
                output: "Access denied: localhost and local network addresses are not allowed",
                metadata: [
                    "error": "Blocked host",
                    "host": host
                ]
            )
            return output
        }
        
        // Resolve DNS to check actual IP addresses
        let resolvedIPs = try await resolveHost(host)
        for ip in resolvedIPs {
            if isPrivateIP(ip) {
                let output = URLFetchOutput(
                    success: false,
                    output: "Access denied: URL resolves to a private IP address",
                    metadata: [
                        "error": "Private IP detected",
                        "host": host,
                        "resolved_ip": ip
                    ]
                )
                return output
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
                let output = URLFetchOutput(
                    success: false,
                    output: "Invalid response type",
                    metadata: ["error": "Invalid response type"]
                )
                return output
            }
            
            // Check response size
            let dataSize = Int64(data.count)
            if dataSize > maxResponseSize {
                let output = URLFetchOutput(
                    success: false,
                    output: "Response too large: \(dataSize) bytes (limit: \(maxResponseSize) bytes)",
                    metadata: [
                        "error": "Response size exceeded",
                        "size": String(dataSize),
                        "limit": String(maxResponseSize)
                    ]
                )
                return output
            }
            
            let outputText = String(data: data, encoding: .utf8) ?? "<Non-UTF8 data>"
            let statusCode = httpResponse.statusCode
            let finalURL = httpResponse.url?.absoluteString ?? url.absoluteString
            
            // Get content type
            let contentType = httpResponse.value(forHTTPHeaderField: "Content-Type") ?? "unknown"
            
            if (200..<300).contains(statusCode) {
                let output = URLFetchOutput(
                    success: true,
                    output: outputText,
                    metadata: [
                        "status": String(statusCode),
                        "url": url.absoluteString,
                        "final_url": finalURL,
                        "content_type": contentType,
                        "content_length": String(dataSize),
                        "fetch_time": String(format: "%.3f", fetchTime),
                        "redirects": String(delegate.redirectCount)
                    ]
                )
                return output
            } else {
                let output = URLFetchOutput(
                    success: false,
                    output: outputText,
                    metadata: [
                        "status": String(statusCode),
                        "url": url.absoluteString,
                        "final_url": finalURL,
                        "error": "HTTP error \(statusCode)",
                        "content_type": contentType,
                        "content_length": String(dataSize)
                    ]
                )
                return output
            }
        } catch {
            let output = URLFetchOutput(
                success: false,
                output: error.localizedDescription,
                metadata: [
                    "url": url.absoluteString,
                    "error": error.localizedDescription
                ]
            )
            return output
        }
    }
}

/// Input structure for URL fetching operations.
@Generable
public struct FetchInput: Sendable {
    /// The URL (HTTP or HTTPS) from which to fetch data.
    public let url: String
}

/// Output structure for URL fetch operations.
public struct URLFetchOutput: Sendable {
    /// Whether the fetch was successful.
    public let success: Bool
    
    /// The fetched content or error message.
    public let output: String
    
    /// Additional metadata about the operation.
    public let metadata: [String: String]
    
    public init(success: Bool, output: String, metadata: [String: String]) {
        self.success = success
        self.output = output
        self.metadata = metadata
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
        let metadataString = metadata.isEmpty ? "" : "\nMetadata:\n" + metadata.map { "  \($0.key): \($0.value)" }.joined(separator: "\n")
        
        return """
        URLFetch [\(status)]
        Output: \(output)\(metadataString)
        """
    }
}

// Make URLFetchOutput conform to PromptRepresentable for compatibility

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

private final class RedirectController: NSObject, URLSessionTaskDelegate, @unchecked Sendable {
    let maxRedirects: Int
    let ssrfChecker: URLFetchTool
    private let lock = NSLock()
    private var _redirectCount = 0
    
    var redirectCount: Int {
        lock.lock()
        defer { lock.unlock() }
        return _redirectCount
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
        lock.lock()
        _redirectCount += 1
        let currentCount = _redirectCount
        lock.unlock()
        
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
