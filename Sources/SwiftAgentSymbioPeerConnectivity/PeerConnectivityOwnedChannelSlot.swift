import Synchronization

/// Shares a newly opened channel with an invocation cancellation handler.
final class PeerConnectivityOwnedChannelSlot: Sendable {
    private let channel = Mutex<PeerConnectivityOwnedChannel?>(nil)

    func store(_ channel: PeerConnectivityOwnedChannel) {
        self.channel.withLock { $0 = channel }
    }

    func current() -> PeerConnectivityOwnedChannel? {
        channel.withLock { $0 }
    }

    func clear(_ channelID: String) {
        channel.withLock { channel in
            guard channel?.id == channelID else {
                return
            }
            channel = nil
        }
    }
}
