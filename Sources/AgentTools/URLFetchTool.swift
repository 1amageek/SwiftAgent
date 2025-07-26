import Foundation
import OpenFoundationModels

/// A tool for fetching data from a URL.
///
/// `URLFetchTool` performs HTTP GET requests to retrieve data from web resources.
///
/// ## Usage Guidance
/// - Use this tool **only** if the user's request requires retrieving **external** data from a web resource.
/// - For trivial tasks (e.g., greetings) or reasoning-based answers that do not require external data,
///   do **not** invoke this tool.
/// - Ensure the URL is valid (HTTP/HTTPS) before calling this tool.
///
/// ## Features
/// - Perform HTTP GET requests in a non-interactive context.
/// - Validate URLs and return the response as plain text.
///
/// ## Limitations
/// - Only supports HTTP and HTTPS URLs.
/// - Cannot handle POST requests, custom headers, or complex configurations.
/// - Does not parse or structure the fetched data; it returns raw text.
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
    
    public static let name = "url_fetch"
    public var name: String { Self.name }
    
    public static let description = """
    A tool for fetching data from a URL. Use this tool to retrieve content from web pages or APIs.
    Limitations:
    - Only supports HTTP and HTTPS URLs.
    - Returns data as plain text.
    - Cannot handle POST requests or custom headers.
    """
    
    public var description: String { Self.description }
    
    public init() {}
    
    public func call(arguments: FetchInput) async throws -> ToolOutput {
        guard let url = URL(string: arguments.url) else {
            let output = URLFetchOutput(
                success: false,
                output: "Invalid URL: \(arguments.url)",
                metadata: ["error": "Invalid URL"]
            )
            return ToolOutput(output)
        }
        
        guard url.scheme == "http" || url.scheme == "https" else {
            let output = URLFetchOutput(
                success: false,
                output: "Unsupported URL scheme: \(url.scheme ?? "nil")",
                metadata: ["error": "Unsupported URL scheme"]
            )
            return ToolOutput(output)
        }
        
        do {
            let (data, response) = try await URLSession.shared.data(from: url)
            
            guard let httpResponse = response as? HTTPURLResponse else {
                let output = URLFetchOutput(
                    success: false,
                    output: "Invalid response type",
                    metadata: ["error": "Invalid response type"]
                )
                return ToolOutput(output)
            }
            
            let outputText = String(data: data, encoding: .utf8) ?? "<Non-UTF8 data>"
            let statusCode = httpResponse.statusCode
            
            if (200..<300).contains(statusCode) {
                let output = URLFetchOutput(
                    success: true,
                    output: outputText,
                    metadata: [
                        "status": String(statusCode),
                        "url": url.absoluteString
                    ]
                )
                return ToolOutput(output)
            } else {
                let output = URLFetchOutput(
                    success: false,
                    output: outputText,
                    metadata: [
                        "status": String(statusCode),
                        "url": url.absoluteString,
                        "error": "HTTP error \(statusCode)"
                    ]
                )
                return ToolOutput(output)
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
            return ToolOutput(output)
        }
    }
}

/// Input structure for URL fetching operations.
@Generable
public struct FetchInput: ConvertibleFromGeneratedContent {
    /// The URL (HTTP or HTTPS) from which to fetch data.
    public let url: String
    
    /// Creates a new instance of `FetchInput`.
    ///
    /// - Parameter url: The URL to fetch data from.
    public init(url: String) {
        self.url = url
    }
}

/// Output structure for URL fetch operations.
public struct URLFetchOutput: Codable, Sendable, CustomStringConvertible {
    /// Whether the fetch was successful.
    public let success: Bool
    
    /// The fetched content or error message.
    public let output: String
    
    /// Additional metadata about the operation.
    public let metadata: [String: String]
    
    /// Creates a new instance of `URLFetchOutput`.
    ///
    /// - Parameters:
    ///   - success: Whether the fetch succeeded.
    ///   - output: The fetched content or error message.
    ///   - metadata: Additional metadata.
    public init(success: Bool, output: String, metadata: [String: String]) {
        self.success = success
        self.output = output
        self.metadata = metadata
    }
    
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
extension URLFetchOutput: PromptRepresentable {
    public var promptRepresentation: Prompt {
        return Prompt(segments: [Prompt.Segment(text: description)])
    }
}