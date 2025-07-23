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
            return ToolOutput("URLFetch [Failed]\nOutput: Invalid URL: \(arguments.url)\nMetadata:\n  error: Invalid URL")
        }
        
        guard url.scheme == "http" || url.scheme == "https" else {
            return ToolOutput("URLFetch [Failed]\nOutput: Unsupported URL scheme: \(url.scheme ?? "nil")\nMetadata:\n  error: Unsupported URL scheme")
        }
        
        do {
            let (data, response) = try await URLSession.shared.data(from: url)
            
            guard let httpResponse = response as? HTTPURLResponse else {
                return ToolOutput("URLFetch [Failed]\nOutput: Invalid response type\nMetadata:\n  error: Invalid response type")
            }
            
            let outputText = String(data: data, encoding: .utf8) ?? "<Non-UTF8 data>"
            let statusCode = httpResponse.statusCode
            
            if (200..<300).contains(statusCode) {
                return ToolOutput("""
                URLFetch [Success]
                Output: \(outputText)
                Metadata:
                  status: \(statusCode)
                  url: \(url.absoluteString)
                """)
            } else {
                return ToolOutput("""
                URLFetch [Failed]
                Output: \(outputText)
                Metadata:
                  status: \(statusCode)
                  url: \(url.absoluteString)
                  error: HTTP error \(statusCode)
                """)
            }
        } catch {
            return ToolOutput("""
            URLFetch [Failed]
            Output: \(error.localizedDescription)
            Metadata:
              url: \(url.absoluteString)
              error: \(error.localizedDescription)
            """)
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