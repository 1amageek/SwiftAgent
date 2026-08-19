import Foundation

public struct URLSessionWebHTTPClient: WebHTTPClient {
    public init() {}

    public func execute(_ request: WebHTTPRequest) async throws -> WebHTTPResponse {
        guard request.maximumBodyBytes > 0 else {
            throw WebHTTPError.invalidBodyLimit(request.maximumBodyBytes)
        }
        guard request.timeout > .zero else {
            throw WebHTTPError.invalidTimeout
        }
        try WebRequestHeaderPolicy.validate(request.headers)

        var urlRequest = URLRequest(url: request.url)
        urlRequest.httpMethod = "GET"
        urlRequest.timeoutInterval = try timeInterval(request.timeout)
        for (name, value) in request.headers {
            urlRequest.setValue(value, forHTTPHeaderField: name)
        }

        let transaction = URLSessionWebTransaction(
            maximumBodyBytes: request.maximumBodyBytes,
            timeout: urlRequest.timeoutInterval
        )
        return try await withTaskCancellationHandler {
            try await transaction.execute(urlRequest)
        } onCancel: {
            transaction.cancel()
        }
    }

    private func timeInterval(_ duration: Duration) throws -> TimeInterval {
        let components = duration.components
        guard components.seconds >= 0, components.attoseconds >= 0 else {
            throw WebHTTPError.invalidTimeout
        }
        let value = TimeInterval(components.seconds)
            + TimeInterval(components.attoseconds) / 1_000_000_000_000_000_000
        guard value > 0, value.isFinite else {
            throw WebHTTPError.invalidTimeout
        }
        return value
    }
}
