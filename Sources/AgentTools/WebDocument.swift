import Foundation

public struct WebDocument: Sendable {
    public let requestedURL: URL
    public let finalURL: URL
    public let statusCode: Int
    public let headers: [String: String]
    public let body: Data
    public let redirectCount: Int
    public let isFromCache: Bool

    public init(
        requestedURL: URL,
        finalURL: URL,
        statusCode: Int,
        headers: [String: String],
        body: Data,
        redirectCount: Int,
        isFromCache: Bool
    ) {
        self.requestedURL = requestedURL
        self.finalURL = finalURL
        self.statusCode = statusCode
        self.headers = headers
        self.body = body
        self.redirectCount = redirectCount
        self.isFromCache = isFromCache
    }

    func markingCached() -> Self {
        Self(
            requestedURL: requestedURL,
            finalURL: finalURL,
            statusCode: statusCode,
            headers: headers,
            body: body,
            redirectCount: redirectCount,
            isFromCache: true
        )
    }
}
