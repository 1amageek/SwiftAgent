//
//  PeerConnectivitySymbioTransport.swift
//  SwiftAgentSymbioPeerConnectivity
//

import Foundation
import NIOCore
import PeerConnectivity
import SwiftAgentSymbio
import Synchronization

public actor PeerConnectivitySymbioTransport: SymbioTransport {
    public static let defaultInvocationProtocolID = "/swiftagent/symbio/invoke/1.0.0"
    public static let defaultDescriptorProtocolID = "/swiftagent/symbio/descriptor/1.0.0"

    public nonisolated var events: AsyncStream<SymbioTransportEvent> {
        eventBroadcaster.subscribe()
    }

    private let session: PeerConnectivitySession
    private let localDescriptor: ParticipantDescriptor
    private let invocationProtocolID: String
    private let descriptorProtocolID: String
    private let eventBroadcaster = SymbioTransportEventBroadcaster()
    private var eventTask: Task<Void, Never>?
    private var peers: [ParticipantID: PeerConnectivityPeer] = [:]
    private var symbioIDsByTransportID: [String: ParticipantID] = [:]
    private var invocationHandler: SymbioIncomingInvocationHandler?
    private let encoder = JSONEncoder()
    private let decoder = JSONDecoder()

    public init(
        session: PeerConnectivitySession,
        localDescriptor: ParticipantDescriptor = ParticipantDescriptor(id: ParticipantID(rawValue: UUID().uuidString), kind: .agent),
        invocationProtocolID: String = PeerConnectivitySymbioTransport.defaultInvocationProtocolID,
        descriptorProtocolID: String = PeerConnectivitySymbioTransport.defaultDescriptorProtocolID
    ) {
        self.session = session
        self.localDescriptor = localDescriptor
        self.invocationProtocolID = invocationProtocolID
        self.descriptorProtocolID = descriptorProtocolID
    }

    public func start() async throws {
        try session.require(.streamMultiplexing)
        try await session.start()
        if eventTask != nil {
            return
        }
        eventTask = Task { [weak self, session] in
            for await event in session.events {
                await self?.handle(event)
            }
        }
    }

    public func shutdown() async throws {
        eventTask?.cancel()
        eventTask = nil
        peers.removeAll()
        symbioIDsByTransportID.removeAll()
        invocationHandler = nil
        defer {
            eventBroadcaster.shutdown()
        }
        try await session.shutdown()
    }

    public func setInvocationHandler(_ handler: @escaping SymbioIncomingInvocationHandler) async {
        invocationHandler = handler
    }

    public func removeInvocationHandler() async {
        invocationHandler = nil
    }

    public func invoke(
        _ envelope: SymbioInvocationEnvelope,
        on peerID: ParticipantID,
        timeout: Duration
    ) async throws -> SymbioInvocationReply {
        guard let peer = peers[peerID] else {
            throw PeerConnectivityError.channelUnavailable
        }

        let request = try encoder.encode(envelope)
        let session = session
        let invocationProtocolID = invocationProtocolID

        return try await withTimeout(timeout) {
            let channel = try await session.openStream(named: invocationProtocolID, to: peer)
            do {
                try await channel.write(Self.buffer(from: request))
                let replyBuffer = try await channel.read()
                let reply = try JSONDecoder().decode(
                    SymbioInvocationReply.self,
                    from: Data(replyBuffer.readableBytesView)
                )
                await self.close(channel)
                return reply
            } catch {
                await self.close(channel)
                throw error
            }
        }
    }

    private nonisolated func close(_ channel: any PeerConnectivityChannel) async {
        do {
            try await channel.close()
        } catch {
            eventBroadcaster.emit(.error(error))
        }
    }

    private func withTimeout<T: Sendable>(
        _ timeout: Duration,
        operation: @escaping @Sendable () async throws -> T
    ) async throws -> T {
        try await withThrowingTaskGroup(of: T.self) { group in
            defer {
                group.cancelAll()
            }
            group.addTask {
                try await operation()
            }
            group.addTask {
                try await Task.sleep(for: timeout)
                throw SymbioError.timeout
            }

            guard let result = try await group.next() else {
                throw SymbioError.timeout
            }
            return result
        }
    }

    private func handle(_ event: PeerConnectivityEvent) async {
        switch event {
        case .peerDiscovered(let peer, _):
            let result = Self.descriptor(from: peer)
            let descriptor = result.descriptor
            register(peer, descriptor: descriptor)
            eventBroadcaster.emit(.peerDiscovered(descriptor))
            if let error = result.error {
                eventBroadcaster.emit(.error(error))
            }
        case .peerLost(let peer):
            let symbioID = unregister(peer)
            eventBroadcaster.emit(.peerLost(symbioID))
        case .peerConnected(let peer):
            let result = Self.descriptor(from: peer)
            let descriptor = result.descriptor
            register(peer, descriptor: descriptor)
            eventBroadcaster.emit(.peerConnected(descriptor.id))
            if let error = result.error {
                eventBroadcaster.emit(.error(error))
            }
            await exchangeDescriptor(with: peer)
        case .peerDisconnected(let peer):
            let symbioID = unregister(peer)
            eventBroadcaster.emit(.peerDisconnected(symbioID))
        case .channelOpened(let channel):
            if channel.protocolID == invocationProtocolID {
                await handleIncomingInvocation(channel)
            } else if channel.protocolID == descriptorProtocolID {
                await handleIncomingDescriptor(channel)
            }
        case .messageReceived,
             .resourceReceived:
            break
        case .error(let error):
            eventBroadcaster.emit(.error(error))
        }
    }

    private func handleIncomingInvocation(_ channel: any PeerConnectivityChannel) async {
        do {
            let requestBuffer = try await channel.read()
            let envelope = try decoder.decode(
                SymbioInvocationEnvelope.self,
                from: Data(requestBuffer.readableBytesView)
            )
            let reply: SymbioInvocationReply
            if let invocationHandler {
                reply = await invocationHandler(envelope, ParticipantID(rawValue: channel.peer.id))
            } else {
                reply = .failure(
                    invocationID: envelope.invocationID,
                    code: SymbioErrorCode.notFound.rawValue,
                    message: "No invocation handler is registered"
                )
            }
            try await channel.write(Self.buffer(from: try encoder.encode(reply)))
        } catch {
            eventBroadcaster.emit(.error(error))
        }
        await close(channel)
    }

    private func exchangeDescriptor(with peer: PeerConnectivityPeer) async {
        let channel: any PeerConnectivityChannel
        do {
            channel = try await session.openStream(named: descriptorProtocolID, to: peer)
        } catch {
            eventBroadcaster.emit(.error(error))
            return
        }

        do {
            try await channel.write(Self.buffer(from: try encoder.encode(localDescriptor)))
            let replyBuffer = try await channel.read()
            let remoteDescriptor = try decoder.decode(
                ParticipantDescriptor.self,
                from: Data(replyBuffer.readableBytesView)
            )
            peers[remoteDescriptor.id] = peer
            symbioIDsByTransportID[peer.id] = remoteDescriptor.id
            eventBroadcaster.emit(.peerDiscovered(remoteDescriptor))
        } catch {
            eventBroadcaster.emit(.error(error))
        }
        await close(channel)
    }

    private func handleIncomingDescriptor(_ channel: any PeerConnectivityChannel) async {
        do {
            let requestBuffer = try await channel.read()
            let remoteDescriptor = try decoder.decode(
                ParticipantDescriptor.self,
                from: Data(requestBuffer.readableBytesView)
            )
            peers[remoteDescriptor.id] = channel.peer
            symbioIDsByTransportID[channel.peer.id] = remoteDescriptor.id
            try await channel.write(Self.buffer(from: try encoder.encode(localDescriptor)))
            eventBroadcaster.emit(.peerDiscovered(remoteDescriptor))
        } catch {
            eventBroadcaster.emit(.error(error))
        }
        await close(channel)
    }

    private func register(_ peer: PeerConnectivityPeer, descriptor: ParticipantDescriptor) {
        peers[ParticipantID(rawValue: peer.id)] = peer
        peers[descriptor.id] = peer
        symbioIDsByTransportID[peer.id] = descriptor.id
    }

    private func unregister(_ peer: PeerConnectivityPeer) -> ParticipantID {
        let descriptor = Self.descriptor(from: peer).descriptor
        let symbioID = symbioIDsByTransportID.removeValue(forKey: peer.id) ?? descriptor.id
        peers.removeValue(forKey: ParticipantID(rawValue: peer.id))
        peers.removeValue(forKey: symbioID)
        return symbioID
    }

    private static func descriptor(from peer: PeerConnectivityPeer) -> DescriptorDecodeResult {
        let metadata = peer.metadata
        if let encoded = metadata[PeerConnectivitySymbioMetadata.descriptor],
           let data = Data(base64Encoded: encoded) {
            do {
                return DescriptorDecodeResult(
                    descriptor: try JSONDecoder().decode(ParticipantDescriptor.self, from: data),
                    error: nil
                )
            } catch {
                return DescriptorDecodeResult(
                    descriptor: fallbackDescriptor(from: peer),
                    error: SymbioError.deserializationFailed(error.localizedDescription)
                )
            }
        }
        return DescriptorDecodeResult(descriptor: fallbackDescriptor(from: peer), error: nil)
    }

    private static func fallbackDescriptor(from peer: PeerConnectivityPeer) -> ParticipantDescriptor {
        let metadata = peer.metadata
        return ParticipantDescriptor(
            id: ParticipantID(rawValue: metadata[PeerConnectivitySymbioMetadata.peerID] ?? peer.id),
            displayName: metadata[PeerConnectivitySymbioMetadata.name] ?? peer.displayName,
            kind: .unknown,
            metadata: metadata
        )
    }

    private static func buffer(from data: Data) -> ByteBuffer {
        var buffer = ByteBuffer()
        buffer.writeBytes(data)
        return buffer
    }
}

private struct DescriptorDecodeResult: Sendable {
    let descriptor: ParticipantDescriptor
    let error: (any Error & Sendable)?
}

public enum PeerConnectivitySymbioMetadata {
    public static let peerID = "symbio.peerID"
    public static let name = "symbio.name"
    public static let descriptor = "symbio.descriptor"

    public static func metadata(for descriptor: ParticipantDescriptor) -> [String: String] {
        var metadata = descriptor.metadata
        metadata[peerID] = descriptor.id.rawValue
        if let descriptorName = descriptor.displayName {
            metadata[name] = descriptorName
        }
        do {
            metadata[self.descriptor] = try JSONEncoder().encode(descriptor).base64EncodedString()
        } catch {
            metadata.removeValue(forKey: self.descriptor)
        }
        return metadata
    }
}

private final class SymbioTransportEventBroadcaster: Sendable {
    private let state = Mutex(BroadcastState())

    private struct Entry: Sendable {
        let id: UInt64
        let continuation: AsyncStream<SymbioTransportEvent>.Continuation
    }

    private struct BroadcastState: Sendable {
        var entries: [Entry] = []
        var nextID: UInt64 = 0
    }

    func subscribe() -> AsyncStream<SymbioTransportEvent> {
        let (stream, continuation) = AsyncStream<SymbioTransportEvent>.makeStream()
        let id = state.withLock { state -> UInt64 in
            let id = state.nextID
            state.nextID += 1
            state.entries.append(Entry(id: id, continuation: continuation))
            return id
        }

        continuation.onTermination = { [weak self] _ in
            self?.state.withLock { state in
                state.entries.removeAll { $0.id == id }
            }
        }
        return stream
    }

    func emit(_ event: SymbioTransportEvent) {
        let entries = state.withLock { $0.entries }
        for entry in entries {
            entry.continuation.yield(event)
        }
    }

    func shutdown() {
        let entries = state.withLock { state -> [Entry] in
            let entries = state.entries
            state.entries.removeAll()
            return entries
        }
        for entry in entries {
            entry.continuation.finish()
        }
    }
}
