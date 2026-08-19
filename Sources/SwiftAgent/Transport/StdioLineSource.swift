import Foundation

/// Owns the asynchronous stdin reader and delegates FIFO state to a buffer.
final class StdioLineSource: Sendable {
    private static let capacity = 256

    private let input: FileHandle
    private let buffer: StdioLineBuffer
    private let readerTask: Task<Void, Never>

    init(input: FileHandle) {
        let buffer = StdioLineBuffer(capacity: Self.capacity)
        self.input = input
        self.buffer = buffer
        self.readerTask = Task {
            do {
                for try await line in input.bytes.lines {
                    guard buffer.enqueue(line) else {
                        return
                    }
                }
                buffer.finish()
            } catch let error as CancellationError {
                if Task.isCancelled {
                    buffer.finish()
                } else {
                    buffer.finish(throwing: .inputReadFailed(
                        error.localizedDescription
                    ))
                }
            } catch {
                buffer.finish(throwing: .inputReadFailed(
                    error.localizedDescription
                ))
            }
        }
    }

    func next() async throws -> String? {
        try await buffer.next()
    }

    func shutdown() async throws {
        buffer.finish()
        readerTask.cancel()
        var closeFailure: AgentConnectionError?
        do {
            try input.close()
        } catch {
            closeFailure = .inputCloseFailed(error.localizedDescription)
        }
        await readerTask.value
        if let closeFailure {
            throw closeFailure
        }
    }
}
