import Foundation
import Synchronization

final class EventDeliveryFailure: Sendable {
    private let storage = Mutex<String?>(nil)

    var errorDescription: String? {
        storage.withLock { $0 }
    }

    func record(_ error: any Error) {
        storage.withLock { description in
            if description == nil {
                description = error.localizedDescription
            }
        }
    }
}
