import Foundation
import PeerConnectivity
import Synchronization

/// Owns the exactly-once shutdown operation for one PeerConnectivity session.
final class PeerConnectivityOwnedSession: Sendable {
    private enum ShutdownState: Sendable {
        case open
        case shuttingDown(id: UUID, task: Task<Void, any Error>)
        case cleanupFailed
        case finished
    }

    private let session: PeerConnectivitySession
    private let shutdownState = Mutex(ShutdownState.open)

    init(_ session: PeerConnectivitySession) {
        self.session = session
    }

    func shutdown() async throws {
        let operation = shutdownState.withLock {
            state -> (id: UUID, task: Task<Void, any Error>)? in
            switch state {
            case .finished:
                return nil
            case .shuttingDown(let id, let task):
                return (id, task)
            case .open, .cleanupFailed:
                let id = UUID()
                let session = self.session
                let task = Task<Void, any Error> {
                    try await session.shutdown()
                }
                state = .shuttingDown(id: id, task: task)
                return (id, task)
            }
        }
        guard let operation else {
            return
        }

        do {
            try await operation.task.value
            shutdownState.withLock { state in
                guard case .shuttingDown(let id, _) = state,
                      id == operation.id else {
                    return
                }
                state = .finished
            }
        } catch {
            shutdownState.withLock { state in
                guard case .shuttingDown(let id, _) = state,
                      id == operation.id else {
                    return
                }
                state = .cleanupFailed
            }
            throw error
        }
    }
}
