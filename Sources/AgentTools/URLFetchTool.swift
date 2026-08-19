import Foundation
import SwiftAgent

public struct URLFetchTool: Tool {
    public typealias Arguments = FetchInput
    public typealias Output = URLFetchOutput

    public static let name = "WebFetch"
    public var name: String { Self.name }

    public static let description = """
        Fetch text from a fully qualified URL authorized by the configured
        destination policy. Redirect destinations are authorized independently.
        Use WebSearch to discover URLs before fetching their full content.
        """

    public var description: String { Self.description }
    public var parameters: GenerationSchema { FetchInput.generationSchema }

    private let fetcher: any WebDocumentFetching

    public init(fetcher: any WebDocumentFetching) {
        self.fetcher = fetcher
    }

    public init(
        trustedOrigins: Set<WebOrigin>,
        client: any WebHTTPClient = URLSessionWebHTTPClient(),
        maximumRedirects: Int = 5,
        cacheConfiguration: WebDocumentCacheConfiguration = .init()
    ) {
        self.fetcher = PolicyEnforcedWebDocumentFetcher(
            client: client,
            policy: TrustedOriginsWebURLPolicy(origins: trustedOrigins),
            maximumRedirects: maximumRedirects,
            cacheConfiguration: cacheConfiguration
        )
    }

    public func call(arguments: FetchInput) async throws -> URLFetchOutput {
        try Task.checkCancellation()
        try TurnCancellationContext.current?.checkCancellation()
        guard let url = URL(string: arguments.url),
              url.scheme != nil,
              url.host != nil else {
            throw WebHTTPError.invalidURL(arguments.url)
        }

        let document = try await fetcher.fetch(WebDocumentRequest(url: url))
        guard (200..<300).contains(document.statusCode) else {
            throw WebHTTPError.httpStatus(document.statusCode)
        }
        guard let text = String(data: document.body, encoding: .utf8) else {
            throw WebHTTPError.unsupportedTextEncoding(
                document.headers["content-type"]
            )
        }

        let contentType = document.headers["content-type"] ?? "unknown"
        let isHTML = contentType.lowercased().contains("text/html")
        let output = isHTML ? try HTMLToMarkdown.convert(text) : text
        return URLFetchOutput(
            content: output,
            requestedURL: document.requestedURL,
            finalURL: document.finalURL,
            statusCode: document.statusCode,
            contentType: contentType,
            bodyByteCount: document.body.count,
            redirectCount: document.redirectCount,
            isFromCache: document.isFromCache,
            convertedToMarkdown: isHTML
        )
    }
}
