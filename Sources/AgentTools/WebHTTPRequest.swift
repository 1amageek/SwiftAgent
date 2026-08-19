import Foundation

public struct WebHTTPRequest: Sendable {
    public let url: URL
    public let headers: [String: String]
    public let timeout: Duration
    public let maximumBodyBytes: Int

    public init(
        url: URL,
        headers: [String: String] = [:],
        timeout: Duration = .seconds(30),
        maximumBodyBytes: Int = 5 * 1_024 * 1_024
    ) {
        self.url = url
        self.headers = headers
        self.timeout = timeout
        self.maximumBodyBytes = maximumBodyBytes
    }
}
