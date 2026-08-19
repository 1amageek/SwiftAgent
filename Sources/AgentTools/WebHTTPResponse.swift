import Foundation

public struct WebHTTPResponse: Sendable {
    public let url: URL
    public let statusCode: Int
    public let headers: [String: String]
    public let body: Data

    public init(
        url: URL,
        statusCode: Int,
        headers: [String: String],
        body: Data
    ) {
        self.url = url
        self.statusCode = statusCode
        self.headers = headers.reduce(into: [:]) { normalized, header in
            normalized[header.key.lowercased()] = header.value
        }
        self.body = body
    }
}
