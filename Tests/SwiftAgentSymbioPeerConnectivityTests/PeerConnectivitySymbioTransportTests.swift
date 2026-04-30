import Foundation
import NIOCore
import PeerConnectivity
import SwiftAgentSymbio
import SwiftAgentSymbioPeerConnectivity
import Synchronization
import Testing

@Suite("PeerConnectivity Symbio Transport Tests")
struct PeerConnectivitySymbioTransportTests {
    @Test
    func metadataRoundTripsParticipantDescriptor() throws {
        let representation = MessageRepresentation.typedPayload(schema: "drone.command")
        let descriptor = ParticipantDescriptor(
            id: "drone.1",
            displayName: "Drone 1",
            kind: .robot,
            representations: [representation],
            capabilityContracts: [
                CapabilityContract(id: "drone.move", input: representation)
            ]
        )

        let metadata = PeerConnectivitySymbioMetadata.metadata(for: descriptor)
        let encoded = try #require(metadata[PeerConnectivitySymbioMetadata.descriptor])
        let data = try #require(Data(base64Encoded: encoded))
        let decoded = try JSONDecoder().decode(ParticipantDescriptor.self, from: data)

        #expect(decoded.id == "drone.1")
        #expect(decoded.displayName == "Drone 1")
        #expect(decoded.capabilityContracts.map(\.id) == ["drone.move"])
    }

    @Test
    func peerDiscoveryMapsMetadataIntoParticipantDescriptor() async throws {
        let backend = MockPeerConnectivityBackend()
        let session = PeerConnectivitySession(backend: backend)
        let transport = PeerConnectivitySymbioTransport(session: session)
        var iterator = transport.events.makeAsyncIterator()
        let descriptor = ParticipantDescriptor(
            id: "agent.peer",
            displayName: "Agent Peer",
            kind: .agent
        )

        try await transport.start()
        await backend.emit(.peerDiscovered(
            PeerConnectivityPeer(
                id: "transport.peer",
                displayName: "Transport Peer",
                metadata: PeerConnectivitySymbioMetadata.metadata(for: descriptor)
            ),
            endpoints: []
        ))

        let event = try await nextEvent(from: &iterator)
        guard case .peerDiscovered(let discovered) = event else {
            Issue.record("expected peerDiscovered")
            return
        }
        #expect(discovered.id == "agent.peer")
        #expect(discovered.displayName == "Agent Peer")
        try await transport.shutdown()
    }

    @Test
    func malformedDescriptorMetadataEmitsFallbackDescriptorAndError() async throws {
        let backend = MockPeerConnectivityBackend()
        let session = PeerConnectivitySession(backend: backend)
        let transport = PeerConnectivitySymbioTransport(session: session)
        var iterator = transport.events.makeAsyncIterator()

        try await transport.start()
        await backend.emit(.peerDiscovered(
            PeerConnectivityPeer(
                id: "transport.peer",
                displayName: "Transport Peer",
                metadata: [
                    PeerConnectivitySymbioMetadata.peerID: "fallback.peer",
                    PeerConnectivitySymbioMetadata.descriptor: Data("{".utf8).base64EncodedString()
                ]
            ),
            endpoints: []
        ))

        let discoveredEvent = try await nextEvent(from: &iterator)
        guard case .peerDiscovered(let discovered) = discoveredEvent else {
            Issue.record("expected peerDiscovered")
            return
        }
        #expect(discovered.id == "fallback.peer")

        let errorEvent = try await nextEvent(from: &iterator)
        guard case .error = errorEvent else {
            Issue.record("expected descriptor decode error")
            return
        }
        try await transport.shutdown()
    }

    @Test
    func invokeResolvesParticipantIDToTransportPeer() async throws {
        let backend = MockPeerConnectivityBackend()
        let session = PeerConnectivitySession(backend: backend)
        let transport = PeerConnectivitySymbioTransport(session: session)
        var iterator = transport.events.makeAsyncIterator()
        let reply = SymbioInvocationReply.success(invocationID: "call-1", result: Data("result".utf8))
        let channel = MockPeerConnectivityChannel(
            peer: PeerConnectivityPeer(id: "transport.peer", displayName: "Transport Peer"),
            protocolID: PeerConnectivitySymbioTransport.defaultInvocationProtocolID,
            reads: [try encode(reply)]
        )
        await backend.setNextChannel(channel)
        let descriptor = ParticipantDescriptor(id: "agent.peer", kind: .agent)

        try await transport.start()
        await backend.emit(.peerDiscovered(
            PeerConnectivityPeer(
                id: "transport.peer",
                displayName: "Transport Peer",
                metadata: PeerConnectivitySymbioMetadata.metadata(for: descriptor)
            ),
            endpoints: []
        ))
        _ = try await nextPeerDiscovered(from: &iterator)

        let envelope = SymbioInvocationEnvelope(
            invocationID: "call-1",
            capability: "agent.action.compute",
            arguments: Data("payload".utf8)
        )
        let received = try await transport.invoke(envelope, on: "agent.peer", timeout: .seconds(1))

        #expect(received.result == Data("result".utf8))
        #expect(await backend.openedPeerIDs() == ["transport.peer"])
        try await transport.shutdown()
    }

    @Test
    func peerLostEmitsParticipantID() async throws {
        let backend = MockPeerConnectivityBackend()
        let session = PeerConnectivitySession(backend: backend)
        let transport = PeerConnectivitySymbioTransport(session: session)
        var iterator = transport.events.makeAsyncIterator()
        let descriptor = ParticipantDescriptor(id: "agent.peer", kind: .agent)
        let peer = PeerConnectivityPeer(
            id: "transport.peer",
            displayName: "Transport Peer",
            metadata: PeerConnectivitySymbioMetadata.metadata(for: descriptor)
        )

        try await transport.start()
        await backend.emit(.peerDiscovered(peer, endpoints: []))
        _ = try await nextPeerDiscovered(from: &iterator)
        await backend.emit(.peerLost(peer))

        let event = try await nextEvent(from: &iterator)
        guard case .peerLost(let peerID) = event else {
            Issue.record("expected peerLost")
            return
        }
        #expect(peerID == "agent.peer")
        try await transport.shutdown()
    }

    @Test
    func shutdownFinishesEventsWhenBackendShutdownThrows() async throws {
        let backend = ThrowingShutdownBackend()
        let session = PeerConnectivitySession(backend: backend)
        let transport = PeerConnectivitySymbioTransport(session: session)
        var iterator = transport.events.makeAsyncIterator()

        try await transport.start()
        do {
            try await transport.shutdown()
            Issue.record("expected shutdown failure")
        } catch {}

        #expect(await iterator.next() == nil)
    }

    @Test
    func incomingInvocationClosesChannelAfterDecodeFailure() async throws {
        let backend = MockPeerConnectivityBackend()
        let session = PeerConnectivitySession(backend: backend)
        let transport = PeerConnectivitySymbioTransport(session: session)
        var iterator = transport.events.makeAsyncIterator()
        var invalid = ByteBuffer()
        invalid.writeString("{")
        let channel = MockPeerConnectivityChannel(
            peer: PeerConnectivityPeer(id: "transport.peer", displayName: "Transport Peer"),
            protocolID: PeerConnectivitySymbioTransport.defaultInvocationProtocolID,
            reads: [invalid]
        )

        try await transport.start()
        await backend.emit(.channelOpened(channel))

        let event = try await nextEvent(from: &iterator)
        guard case .error = event else {
            Issue.record("expected decode error")
            return
        }
        #expect(channel.closeCount() == 1)
        try await transport.shutdown()
    }
}

private enum TestBackendError: Error {
    case shutdownFailed
}

private actor MockPeerConnectivityBackend: PeerConnectivityBackend {
    nonisolated let capabilities: PeerConnectivityCapabilities = [.streamMultiplexing]
    nonisolated let events: AsyncStream<PeerConnectivityEvent>
    private let continuation: AsyncStream<PeerConnectivityEvent>.Continuation
    private var nextChannel: (any PeerConnectivityChannel)?
    private var openedPeers: [String] = []

    init() {
        let stream = AsyncStream<PeerConnectivityEvent>.makeStream()
        self.events = stream.stream
        self.continuation = stream.continuation
    }

    func start() async throws {}

    func shutdown() async throws {
        continuation.finish()
    }

    func connect(to endpoint: PeerConnectivityEndpoint) async throws -> PeerConnectivityPeer {
        throw PeerConnectivityError.unsupportedOperation("connect")
    }

    func disconnect(from peer: PeerConnectivityPeer) async throws {}

    func send(
        _ bytes: ByteBuffer,
        to peer: PeerConnectivityPeer,
        mode: PeerSendMode
    ) async throws {}

    func openChannel(
        to peer: PeerConnectivityPeer,
        protocol protocolID: String
    ) async throws -> any PeerConnectivityChannel {
        openedPeers.append(peer.id)
        if let nextChannel {
            self.nextChannel = nil
            return nextChannel
        }
        throw PeerConnectivityError.channelUnavailable
    }

    func sendResource(_ resource: PeerResource, to peer: PeerConnectivityPeer) async throws {}

    func setNextChannel(_ channel: any PeerConnectivityChannel) {
        nextChannel = channel
    }

    func openedPeerIDs() -> [String] {
        openedPeers
    }

    func emit(_ event: PeerConnectivityEvent) {
        continuation.yield(event)
    }
}

private actor ThrowingShutdownBackend: PeerConnectivityBackend {
    nonisolated let capabilities: PeerConnectivityCapabilities = [.streamMultiplexing]
    nonisolated let events: AsyncStream<PeerConnectivityEvent>
    private let continuation: AsyncStream<PeerConnectivityEvent>.Continuation

    init() {
        let stream = AsyncStream<PeerConnectivityEvent>.makeStream()
        self.events = stream.stream
        self.continuation = stream.continuation
    }

    func start() async throws {}

    func shutdown() async throws {
        continuation.finish()
        throw TestBackendError.shutdownFailed
    }

    func connect(to endpoint: PeerConnectivityEndpoint) async throws -> PeerConnectivityPeer {
        throw PeerConnectivityError.unsupportedOperation("connect")
    }

    func disconnect(from peer: PeerConnectivityPeer) async throws {}

    func send(
        _ bytes: ByteBuffer,
        to peer: PeerConnectivityPeer,
        mode: PeerSendMode
    ) async throws {}

    func openChannel(
        to peer: PeerConnectivityPeer,
        protocol protocolID: String
    ) async throws -> any PeerConnectivityChannel {
        throw PeerConnectivityError.channelUnavailable
    }

    func sendResource(_ resource: PeerResource, to peer: PeerConnectivityPeer) async throws {}
}

private final class MockPeerConnectivityChannel: PeerConnectivityChannel, Sendable {
    let peer: PeerConnectivityPeer
    let protocolID: String?
    private let state: Mutex<State>

    private struct State: Sendable {
        var reads: [ByteBuffer]
        var writes: [ByteBuffer] = []
        var closeCount = 0
    }

    init(
        peer: PeerConnectivityPeer,
        protocolID: String?,
        reads: [ByteBuffer]
    ) {
        self.peer = peer
        self.protocolID = protocolID
        self.state = Mutex(State(reads: reads))
    }

    func read() async throws -> ByteBuffer {
        try state.withLock { state in
            guard !state.reads.isEmpty else {
                throw PeerConnectivityError.channelUnavailable
            }
            return state.reads.removeFirst()
        }
    }

    func write(_ bytes: ByteBuffer) async throws {
        state.withLock { state in
            state.writes.append(bytes)
        }
    }

    func close() async throws {
        state.withLock { state in
            state.closeCount += 1
        }
    }

    func closeCount() -> Int {
        state.withLock { state in
            state.closeCount
        }
    }
}

private func nextEvent(
    from iterator: inout AsyncStream<SymbioTransportEvent>.Iterator
) async throws -> SymbioTransportEvent {
    guard let event = await iterator.next() else {
        throw PeerConnectivityError.channelClosed
    }
    return event
}

private func nextPeerDiscovered(
    from iterator: inout AsyncStream<SymbioTransportEvent>.Iterator
) async throws -> ParticipantDescriptor {
    for _ in 0..<5 {
        let event = try await nextEvent(from: &iterator)
        if case .peerDiscovered(let descriptor) = event {
            return descriptor
        }
    }
    throw PeerConnectivityError.channelUnavailable
}

private func encode<T: Encodable>(_ value: T) throws -> ByteBuffer {
    let data = try JSONEncoder().encode(value)
    var buffer = ByteBuffer()
    buffer.writeBytes(data)
    return buffer
}
