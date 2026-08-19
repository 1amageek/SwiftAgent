import Foundation
import Synchronization

final class URLSessionWebTransaction: NSObject, URLSessionDataDelegate, Sendable {
    private struct State: Sendable {
        var continuation: CheckedContinuation<WebHTTPResponse, any Error>?
        var session: URLSession?
        var task: URLSessionDataTask?
        var response: HTTPURLResponse?
        var body = Data()
        var isCancelled = false
        var invalidationRequested = false
        var isFinished = false
        var terminalResult: Result<WebHTTPResponse, any Error>?
    }

    private struct Completion: Sendable {
        let continuation: CheckedContinuation<WebHTTPResponse, any Error>
        let result: Result<WebHTTPResponse, any Error>
    }

    private let maximumBodyBytes: Int
    private let timeout: TimeInterval
    private let state = Mutex(State())

    init(maximumBodyBytes: Int, timeout: TimeInterval) {
        self.maximumBodyBytes = maximumBodyBytes
        self.timeout = timeout
    }

    func execute(_ request: URLRequest) async throws -> WebHTTPResponse {
        try await withCheckedThrowingContinuation { continuation in
            let configuration = URLSessionConfiguration.ephemeral
            configuration.timeoutIntervalForRequest = timeout
            configuration.timeoutIntervalForResource = timeout
            configuration.waitsForConnectivity = false
            configuration.httpMaximumConnectionsPerHost = 1
            configuration.requestCachePolicy = .reloadIgnoringLocalCacheData
            configuration.httpShouldSetCookies = false
            configuration.httpCookieStorage = nil
            configuration.urlCredentialStorage = nil
            configuration.urlCache = nil

            let session = URLSession(
                configuration: configuration,
                delegate: self,
                delegateQueue: nil
            )
            let task = session.dataTask(with: request)
            let cancelled = state.withLock { state -> Bool in
                guard !state.isFinished else {
                    return true
                }
                state.continuation = continuation
                state.session = session
                state.task = task
                return state.isCancelled
            }
            if cancelled {
                complete(
                    .failure(CancellationError()),
                    cancellingOutstandingTasks: true
                )
            } else {
                task.resume()
            }
        }
    }

    func cancel() {
        let resources = state.withLock {
            state -> (URLSessionDataTask?, URLSession?) in
            state.isCancelled = true
            guard !state.isFinished, let session = state.session else {
                return (nil, nil)
            }
            state.terminalResult = .failure(CancellationError())
            state.invalidationRequested = true
            return (state.task, session)
        }
        resources.0?.cancel()
        resources.1?.invalidateAndCancel()
    }

    func urlSession(
        _ session: URLSession,
        task: URLSessionTask,
        willPerformHTTPRedirection response: HTTPURLResponse,
        newRequest request: URLRequest,
        completionHandler: @escaping @Sendable (URLRequest?) -> Void
    ) {
        state.withLock { state in
            guard !state.isFinished else {
                return
            }
            state.response = response
        }
        completionHandler(nil)
    }

    func urlSession(
        _ session: URLSession,
        dataTask: URLSessionDataTask,
        didReceive response: URLResponse,
        completionHandler: @escaping @Sendable (URLSession.ResponseDisposition) -> Void
    ) {
        guard let httpResponse = response as? HTTPURLResponse else {
            completionHandler(.cancel)
            complete(
                .failure(WebHTTPError.invalidResponse),
                cancellingOutstandingTasks: true
            )
            return
        }
        let expectedLength = httpResponse.expectedContentLength
        guard expectedLength < 0
                || expectedLength <= Int64(maximumBodyBytes) else {
            completionHandler(.cancel)
            complete(
                .failure(WebHTTPError.responseTooLarge(
                    actual: expectedLength,
                    maximum: maximumBodyBytes
                )),
                cancellingOutstandingTasks: true
            )
            return
        }

        state.withLock { state in
            guard !state.isFinished else {
                return
            }
            state.response = httpResponse
            if expectedLength > 0 {
                state.body.reserveCapacity(Int(expectedLength))
            }
        }
        completionHandler(.allow)
    }

    func urlSession(
        _ session: URLSession,
        dataTask: URLSessionDataTask,
        didReceive data: Data
    ) {
        let exceeded = state.withLock { state -> Bool in
            guard !state.isFinished else {
                return false
            }
            guard data.count <= maximumBodyBytes - state.body.count else {
                return true
            }
            state.body.append(data)
            return false
        }
        if exceeded {
            dataTask.cancel()
            complete(
                .failure(WebHTTPError.responseTooLarge(
                    actual: nil,
                    maximum: maximumBodyBytes
                )),
                cancellingOutstandingTasks: true
            )
        }
    }

    func urlSession(
        _ session: URLSession,
        task: URLSessionTask,
        didCompleteWithError error: (any Error)?
    ) {
        if let error {
            let cancelled = state.withLock { $0.isCancelled }
            if cancelled {
                complete(
                    .failure(CancellationError()),
                    cancellingOutstandingTasks: true
                )
            } else {
                complete(.failure(WebHTTPError.transport(
                    error.localizedDescription
                )))
            }
            return
        }

        let result = state.withLock {
            state -> Result<WebHTTPResponse, any Error> in
            guard let response = state.response,
                  let url = response.url else {
                return .failure(WebHTTPError.invalidResponse)
            }
            var headers: [String: String] = [:]
            for (name, value) in response.allHeaderFields {
                headers[String(describing: name).lowercased()] = String(
                    describing: value
                )
            }
            return .success(WebHTTPResponse(
                url: url,
                statusCode: response.statusCode,
                headers: headers,
                body: state.body
            ))
        }
        complete(result)
    }

    func urlSession(
        _ session: URLSession,
        didBecomeInvalidWithError error: (any Error)?
    ) {
        let completion = state.withLock { state -> Completion? in
            guard !state.isFinished,
                  state.session === session,
                  let continuation = state.continuation else {
                return nil
            }
            state.isFinished = true
            state.continuation = nil
            state.task = nil
            state.session = nil
            let result: Result<WebHTTPResponse, any Error>
            if state.isCancelled {
                result = .failure(CancellationError())
            } else if let error {
                result = .failure(WebHTTPError.transport(
                    error.localizedDescription
                ))
            } else {
                result = state.terminalResult
                    ?? .failure(WebHTTPError.invalidResponse)
            }
            state.terminalResult = nil
            return Completion(
                continuation: continuation,
                result: result
            )
        }
        guard let completion else {
            return
        }
        completion.continuation.resume(with: completion.result)
    }

    private func complete(
        _ result: Result<WebHTTPResponse, any Error>,
        cancellingOutstandingTasks: Bool = false
    ) {
        let session = state.withLock { state -> URLSession? in
            guard !state.isFinished, state.terminalResult == nil else {
                return nil
            }
            state.terminalResult = state.isCancelled
                ? .failure(CancellationError())
                : result
            state.task = nil
            guard !state.invalidationRequested else {
                return nil
            }
            state.invalidationRequested = true
            return state.session
        }
        guard let session else {
            return
        }
        if cancellingOutstandingTasks {
            session.invalidateAndCancel()
        } else {
            session.finishTasksAndInvalidate()
        }
    }
}
