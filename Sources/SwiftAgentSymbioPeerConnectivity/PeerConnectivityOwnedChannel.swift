import Foundation
import PeerConnectivity
import Synchronization

/// Owns one PeerConnectivity channel and serializes retryable close attempts.
final class PeerConnectivityOwnedChannel: Sendable {
    private enum CloseState: Sendable {
        case open
        case closing(id: String, task: Task<Void, any Error>)
        case cleanupFailed
        case closed
    }

    let id: String
    let value: any PeerConnectivityChannel
    private let closeState = Mutex(CloseState.open)

    init(_ value: any PeerConnectivityChannel) {
        self.id = UUID().uuidString
        self.value = value
    }

    func close() async throws {
        let operation = closeState.withLock {
            state -> (id: String, task: Task<Void, any Error>)? in
            switch state {
            case .closed:
                return nil
            case .closing(let id, let task):
                return (id, task)
            case .open, .cleanupFailed:
                let id = UUID().uuidString
                let channel = value
                let task = Task<Void, any Error> {
                    try await channel.close()
                }
                state = .closing(id: id, task: task)
                return (id, task)
            }
        }
        guard let operation else {
            return
        }
        do {
            try await operation.task.value
            closeState.withLock { state in
                guard case .closing(let id, _) = state,
                      id == operation.id else {
                    return
                }
                state = .closed
            }
        } catch {
            closeState.withLock { state in
                guard case .closing(let id, _) = state,
                      id == operation.id else {
                    return
                }
                state = .cleanupFailed
            }
            throw error
        }
    }
}
