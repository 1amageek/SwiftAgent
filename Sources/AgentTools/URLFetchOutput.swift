import Foundation
import SwiftAgent

public struct URLFetchOutput: Sendable {
    public let content: String
    public let requestedURL: URL
    public let finalURL: URL
    public let statusCode: Int
    public let contentType: String
    public let bodyByteCount: Int
    public let redirectCount: Int
    public let isFromCache: Bool
    public let convertedToMarkdown: Bool

    public init(
        content: String,
        requestedURL: URL,
        finalURL: URL,
        statusCode: Int,
        contentType: String,
        bodyByteCount: Int,
        redirectCount: Int,
        isFromCache: Bool,
        convertedToMarkdown: Bool
    ) {
        self.content = content
        self.requestedURL = requestedURL
        self.finalURL = finalURL
        self.statusCode = statusCode
        self.contentType = contentType
        self.bodyByteCount = bodyByteCount
        self.redirectCount = redirectCount
        self.isFromCache = isFromCache
        self.convertedToMarkdown = convertedToMarkdown
    }
}

extension URLFetchOutput: PromptRepresentable {
    public var promptRepresentation: Prompt {
        Prompt(description)
    }
}

extension URLFetchOutput: CustomStringConvertible {
    public var description: String {
        return """
            WebFetch
            URL: \(finalURL.absoluteString)
            Status: \(statusCode)
            Content-Type: \(contentType)
            Bytes: \(bodyByteCount)
            Redirects: \(redirectCount)
            Cached: \(isFromCache)

            \(content)
            """
    }
}
