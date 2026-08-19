import Foundation
import NIOCore
import NetworkingCore
import NetworkingTime
import PeerConnectivity
import Synchronization
import Testing
@testable import SwiftAgentSymbio
@testable import SwiftAgentSymbioPeerConnectivity

@Suite("PeerConnectivity Symbio link")
struct PeerConnectivitySymbioLinkTests {
    @Test("Invalid capacities fail before the backend starts", .timeLimit(.minutes(1)))
    func invalidCapacityFailsClosed() async throws {
        let backend = MockPeerConnectivityBackend()
        let link = PeerConnectivitySymbioLink(
            session: PeerConnectivitySession(backend: backend),
            maximumConcurrentOperations: 0
        )

        await #expect(throws: PeerConnectivitySymbioError.self) {
            try await link.start()
        }
        #expect(await backend.startCount() == 0)
        try await link.shutdown()
    }

    @Test("Cancelled startup owns and drains session cleanup", .timeLimit(.minutes(1)))
    func cancelledStartupDrainsSessionCleanup() async throws {
        let backend = MockPeerConnectivityBackend(blocksStart: true)
        let link = PeerConnectivitySymbioLink(
            session: PeerConnectivitySession(backend: backend),
            channelOperationTimeout: .seconds(60)
        )

        let startup = Task {
            try await link.start()
        }
        await backend.waitUntilStartStarted()
        startup.cancel()

        await #expect(throws: CancellationError.self) {
            try await startup.value
        }
        #expect(await backend.shutdownCount == 1)
        #expect(await backend.shutdownObservedCancellation == false)
        try await link.shutdown()
    }

    @Test("Unexpected backend startup cancellation is a failure", .timeLimit(.minutes(1)))
    func unexpectedBackendStartupCancellationIsFailure() async throws {
        let backend = MockPeerConnectivityBackend(
            startError: CancellationError()
        )
        let link = PeerConnectivitySymbioLink(
            session: PeerConnectivitySession(backend: backend)
        )

        await #expect(throws: PeerConnectivitySymbioError.self) {
            try await link.start()
        }
        #expect(await backend.shutdownCount == 1)
    }

    @Test("Inbound announcement remains an unverified transport claim", .timeLimit(.minutes(1)))
    func announcementProducesTransportClaim() async throws {
        let backend = MockPeerConnectivityBackend()
        let link = PeerConnectivitySymbioLink(
            session: PeerConnectivitySession(backend: backend)
        )
        try await link.start()

        let peer = remotePeer()
        await backend.emit(.peerConnected(peer))
        _ = try await link.receive()
        let descriptor = ParticipantDescriptor(id: "participant.remote", kind: .agent)
        let channel = MockPeerConnectivityChannel(
            peer: peer,
            protocolID: PeerConnectivitySymbioLink.defaultAnnouncementProtocolID,
            reads: [try encode(SymbioWireAnnouncement.publish(descriptor))]
        )
        await backend.emit(.channelOpened(channel))

        guard case .peerClaimed(let claim) = try await link.receive() else {
            Issue.record("Expected an unverified participant claim")
            try await link.shutdown()
            return
        }
        #expect(claim.transportPeerID == "transport.remote")
        #expect(claim.descriptor.id == "participant.remote")
        #expect(claim.authentication.subject == "authenticated.remote")
        #expect(channel.closeCount() == 1)
        try await link.shutdown()
    }

    @Test("Outbound invocation addresses only the transport peer binding", .timeLimit(.minutes(1)))
    func invocationUsesTransportPeerID() async throws {
        let backend = MockPeerConnectivityBackend()
        let link = PeerConnectivitySymbioLink(
            session: PeerConnectivitySession(backend: backend)
        )
        try await link.start()
        let peer = remotePeer()
        await backend.emit(.peerConnected(peer))
        _ = try await link.receive()

        let envelope = SymbioInvocationEnvelope(
            senderID: "runtime.local",
            recipientID: "participant.remote",
            capability: "test.echo",
            representation: .typedPayload(schema: "test.echo"),
            arguments: OwnedBytes(consuming: Array("payload".utf8)),
            executionBudget: .seconds(1)
        )
        let expectedReply = SymbioInvocationReply.success(
            invocationID: envelope.invocationID,
            result: envelope.arguments
        )
        let channel = MockPeerConnectivityChannel(
            peer: peer,
            protocolID: PeerConnectivitySymbioLink.defaultInvocationProtocolID,
            reads: [try encode(SymbioWireInvocationReply(expectedReply))]
        )
        await backend.setNextChannel(channel)

        let reply = try await link.invoke(
            envelope,
            on: "transport.remote",
            timeout: .seconds(1)
        )

        #expect(reply == expectedReply)
        #expect(await backend.openedPeerIDs() == ["transport.remote"])
        #expect(channel.closeCount() == 1)

        let requestReader = MockPeerConnectivityChannel(
            peer: peer,
            protocolID: PeerConnectivitySymbioLink.defaultInvocationProtocolID,
            reads: channel.writtenFrames()
        )
        let requestData = try await SymbioWireFrameCodec(
            maximumPayloadBytes: 4 * 1_024 * 1_024
        ).readFrame(from: requestReader)
        let decodedRequest = try JSONDecoder().decode(
            SymbioWireInvocationEnvelope.self,
            from: requestData
        ).value()
        #expect(decodedRequest == envelope)
        try await link.shutdown()
    }

    @Test("Fragmented invocation replies are reassembled", .timeLimit(.minutes(1)))
    func fragmentedInvocationReplyIsReassembled() async throws {
        let backend = MockPeerConnectivityBackend()
        let link = PeerConnectivitySymbioLink(
            session: PeerConnectivitySession(backend: backend)
        )
        try await link.start()
        let peer = remotePeer()
        await backend.emit(.peerConnected(peer))
        _ = try await link.receive()

        let envelope = SymbioInvocationEnvelope(
            senderID: "runtime.local",
            recipientID: "participant.remote",
            capability: "test.echo",
            representation: .typedPayload(schema: "test.echo"),
            arguments: OwnedBytes(consuming: Array("payload".utf8)),
            executionBudget: .seconds(1)
        )
        let expectedReply = SymbioInvocationReply.success(
            invocationID: envelope.invocationID,
            result: envelope.arguments
        )
        let framedReply = try encode(SymbioWireInvocationReply(expectedReply))
        let channel = MockPeerConnectivityChannel(
            peer: peer,
            protocolID: PeerConnectivitySymbioLink.defaultInvocationProtocolID,
            reads: split(framedReply, chunkSizes: [1, 2, 1, 3])
        )
        await backend.setNextChannel(channel)

        let reply = try await link.invoke(
            envelope,
            on: "transport.remote",
            timeout: .seconds(1)
        )

        #expect(reply == expectedReply)
        #expect(channel.readCount() > 4)
        try await link.shutdown()
    }

    @Test("Malformed invocation replies use the typed wire error", .timeLimit(.minutes(1)))
    func malformedInvocationReplyIsTyped() async throws {
        let backend = MockPeerConnectivityBackend()
        let link = PeerConnectivitySymbioLink(
            session: PeerConnectivitySession(backend: backend)
        )
        try await link.start()
        let peer = remotePeer()
        await backend.emit(.peerConnected(peer))
        _ = try await link.receive()

        let channel = MockPeerConnectivityChannel(
            peer: peer,
            protocolID: PeerConnectivitySymbioLink.defaultInvocationProtocolID,
            reads: [try frame(Data("not-json".utf8))]
        )
        await backend.setNextChannel(channel)
        let envelope = SymbioInvocationEnvelope(
            senderID: "runtime.local",
            recipientID: "participant.remote",
            capability: "test.echo",
            representation: .typedPayload(schema: "test.echo"),
            arguments: OwnedBytes(consuming: []),
            executionBudget: .seconds(1)
        )

        do {
            _ = try await link.invoke(
                envelope,
                on: "transport.remote",
                timeout: .seconds(1)
            )
            Issue.record("Expected malformed JSON to fail")
        } catch let error as PeerConnectivitySymbioError {
            guard case .invalidWireMessage = error else {
                Issue.record("Unexpected typed error: \(error)")
                try await link.shutdown()
                return
            }
        } catch {
            Issue.record("Concrete decoding error escaped the adapter: \(error)")
        }
        #expect(channel.closeCount() == 1)
        try await link.shutdown()
    }

    @Test(
        "Oversized declared frames fail before reading a payload",
        .timeLimit(.minutes(1))
    )
    func oversizedDeclaredFrameFailsBeforePayloadRead() async {
        let codec = SymbioWireFrameCodec(maximumPayloadBytes: 16)
        var header = ByteBuffer()
        header.writeInteger(UInt32(17), endianness: .big)
        let channel = MockPeerConnectivityChannel(
            peer: remotePeer(),
            protocolID: PeerConnectivitySymbioLink.defaultInvocationProtocolID,
            reads: [header]
        )

        do {
            _ = try await codec.readFrame(from: channel)
            Issue.record("Expected the declared payload length to be rejected")
        } catch let error as PeerConnectivitySymbioError {
            guard case .wireMessageTooLarge(let actual, let maximum) = error else {
                Issue.record("Unexpected framing error: \(error)")
                return
            }
            #expect(actual == 17)
            #expect(maximum == 16)
        } catch {
            Issue.record("Unexpected error: \(error)")
        }
        #expect(channel.readCount() == 1)
    }

    @Test("Peer identity replacement emits disconnect before reconnect", .timeLimit(.minutes(1)))
    func peerIdentityReplacementIsAnExplicitGenerationChange() async throws {
        let backend = MockPeerConnectivityBackend()
        let link = PeerConnectivitySymbioLink(
            session: PeerConnectivitySession(backend: backend)
        )
        try await link.start()

        let original = remotePeer()
        let replacement = PeerConnectivityPeer(
            id: original.id,
            displayName: "Replacement",
            identity: .backend(kind: "test", value: "replacement.identity")
        )
        await backend.emit(.peerConnected(original))
        guard case .peerConnected(_) = try await link.receive() else {
            Issue.record("Expected the original peer connection")
            try await link.shutdown()
            return
        }

        await backend.emit(.peerConnected(replacement))
        guard case .peerDisconnected(let disconnectedID) = try await link.receive() else {
            Issue.record("Expected identity replacement to disconnect the old generation")
            try await link.shutdown()
            return
        }
        #expect(disconnectedID == "transport.remote")
        guard case .peerConnected(let connectedID) = try await link.receive() else {
            Issue.record("Expected the replacement peer generation")
            try await link.shutdown()
            return
        }
        #expect(connectedID == "transport.remote")

        await backend.emit(.peerDisconnected(original))
        guard case .diagnostic(let diagnostic) = try await link.receive() else {
            Issue.record("Expected the stale disconnect to be diagnosed")
            try await link.shutdown()
            return
        }
        #expect(diagnostic.contains("stale disconnect"))
        try await link.shutdown()
    }

    @Test("Outbound channel identity must match the connected peer", .timeLimit(.minutes(1)))
    func outboundChannelIdentityMismatchIsRejected() async throws {
        let backend = MockPeerConnectivityBackend()
        let link = PeerConnectivitySymbioLink(
            session: PeerConnectivitySession(backend: backend)
        )
        try await link.start()
        let peer = remotePeer()
        await backend.emit(.peerConnected(peer))
        _ = try await link.receive()

        let wrongPeer = PeerConnectivityPeer(
            id: peer.id,
            displayName: "Wrong",
            identity: .backend(kind: "test", value: "wrong.identity")
        )
        let channel = MockPeerConnectivityChannel(
            peer: wrongPeer,
            protocolID: PeerConnectivitySymbioLink.defaultInvocationProtocolID,
            reads: []
        )
        await backend.setNextChannel(channel)
        let envelope = SymbioInvocationEnvelope(
            senderID: "runtime.local",
            recipientID: "participant.remote",
            capability: "test.echo",
            representation: .typedPayload(schema: "test.echo"),
            arguments: OwnedBytes(consuming: []),
            executionBudget: .seconds(1)
        )

        await #expect(throws: PeerConnectivitySymbioError.self) {
            _ = try await link.invoke(
                envelope,
                on: "transport.remote",
                timeout: .seconds(1)
            )
        }
        #expect(channel.closeCount() == 1)
        try await link.shutdown()
    }

    @Test("Outbound replies must preserve invocation correlation", .timeLimit(.minutes(1)))
    func outboundReplyCorrelationMismatchIsRejected() async throws {
        let backend = MockPeerConnectivityBackend()
        let link = PeerConnectivitySymbioLink(
            session: PeerConnectivitySession(backend: backend)
        )
        try await link.start()
        let peer = remotePeer()
        await backend.emit(.peerConnected(peer))
        _ = try await link.receive()

        let envelope = SymbioInvocationEnvelope(
            senderID: "runtime.local",
            recipientID: "participant.remote",
            capability: "test.echo",
            representation: .typedPayload(schema: "test.echo"),
            arguments: OwnedBytes(consuming: []),
            executionBudget: .seconds(1)
        )
        let mismatchedReply = SymbioInvocationReply.success(
            invocationID: "different.invocation",
            result: nil
        )
        let channel = MockPeerConnectivityChannel(
            peer: peer,
            protocolID: PeerConnectivitySymbioLink.defaultInvocationProtocolID,
            reads: [try encode(SymbioWireInvocationReply(mismatchedReply))]
        )
        await backend.setNextChannel(channel)

        await #expect(throws: PeerConnectivitySymbioError.self) {
            _ = try await link.invoke(
                envelope,
                on: "transport.remote",
                timeout: .seconds(1)
            )
        }
        #expect(channel.closeCount() == 1)
        try await link.shutdown()
    }

    @Test("Malformed invocation is reported and its channel is closed", .timeLimit(.minutes(1)))
    func malformedInvocationIsExplicit() async throws {
        let backend = MockPeerConnectivityBackend()
        let link = PeerConnectivitySymbioLink(
            session: PeerConnectivitySession(backend: backend)
        )
        try await link.start()
        await backend.emit(.peerConnected(remotePeer()))
        _ = try await link.receive()
        let channel = MockPeerConnectivityChannel(
            peer: remotePeer(),
            protocolID: PeerConnectivitySymbioLink.defaultInvocationProtocolID,
            reads: [try frame(Data("not-json".utf8))]
        )
        await backend.emit(.channelOpened(channel))

        guard case .diagnostic(let message) = try await link.receive() else {
            Issue.record("Expected a wire decoding diagnostic")
            try await link.shutdown()
            return
        }
        #expect(message.contains("Failed to receive invocation"))
        #expect(channel.closeCount() == 1)
        try await link.shutdown()
    }

    @Test("Wire identifiers are validated before entering the link")
    func emptyWireIdentifiersAreRejected() throws {
        let envelope = SymbioInvocationEnvelope(
            invocationID: " ",
            senderID: "sender",
            recipientID: "recipient",
            capability: "test.echo",
            representation: .typedPayload(schema: "test.echo"),
            arguments: OwnedBytes(consuming: []),
            executionBudget: .seconds(1)
        )
        #expect(throws: PeerConnectivitySymbioError.self) {
            _ = try SymbioWireInvocationEnvelope(envelope).value()
        }

        let reply = SymbioInvocationReply.success(
            invocationID: "\n",
            result: nil
        )
        #expect(throws: PeerConnectivitySymbioError.self) {
            _ = try SymbioWireInvocationReply(reply).value()
        }

        #expect(throws: PeerConnectivitySymbioError.self) {
            _ = try SymbioWireAnnouncement.withdraw("\t").validated()
        }
    }

    @Test("Failed channel close remains owned until shutdown retry", .timeLimit(.minutes(1)))
    func channelCloseFailureIsRetried() async throws {
        let backend = MockPeerConnectivityBackend()
        let link = PeerConnectivitySymbioLink(
            session: PeerConnectivitySession(backend: backend)
        )
        try await link.start()
        await backend.emit(.peerConnected(remotePeer()))
        _ = try await link.receive()
        let descriptor = ParticipantDescriptor(id: "participant.remote", kind: .agent)
        let channel = MockPeerConnectivityChannel(
            peer: remotePeer(),
            protocolID: PeerConnectivitySymbioLink.defaultAnnouncementProtocolID,
            reads: [try encode(SymbioWireAnnouncement.publish(descriptor))],
            closeFailures: 1
        )
        await backend.emit(.channelOpened(channel))

        _ = try await link.receive()
        guard case .diagnostic(let message) = try await link.receive() else {
            Issue.record("Expected a channel cleanup diagnostic")
            try await link.shutdown()
            return
        }
        #expect(message.contains("Failed to close announcement channel"))

        try await link.shutdown()
        #expect(channel.closeCount() == 2)
    }

    @Test("Backend shutdown failures remain observable", .timeLimit(.minutes(1)))
    func shutdownFailureIsNotDiscarded() async throws {
        let backend = MockPeerConnectivityBackend(shutdownError: TestBackendError.shutdown)
        let link = PeerConnectivitySymbioLink(
            session: PeerConnectivitySession(backend: backend)
        )
        try await link.start()

        await #expect(throws: PeerConnectivitySymbioError.self) {
            try await link.shutdown()
        }
        await #expect(throws: PeerConnectivitySymbioError.self) {
            try await link.receive()
        }
    }

    @Test("Shutdown closes active invocation channels before draining I/O", .timeLimit(.minutes(1)))
    func shutdownUnblocksActiveInvocation() async throws {
        let backend = MockPeerConnectivityBackend()
        let link = PeerConnectivitySymbioLink(
            session: PeerConnectivitySession(backend: backend)
        )
        try await link.start()
        let peer = remotePeer()
        await backend.emit(.peerConnected(peer))
        _ = try await link.receive()

        let channel = BlockingPeerConnectivityChannel(
            peer: peer,
            protocolID: PeerConnectivitySymbioLink.defaultInvocationProtocolID
        )
        await backend.setNextChannel(channel)
        let envelope = SymbioInvocationEnvelope(
            senderID: "runtime.local",
            recipientID: "participant.remote",
            capability: "test.echo",
            representation: .typedPayload(schema: "test.echo"),
            arguments: OwnedBytes(consuming: Array("payload".utf8)),
            executionBudget: .seconds(60)
        )
        let invocation = Task {
            try await link.invoke(
                envelope,
                on: "transport.remote",
                timeout: .seconds(60)
            )
        }
        await channel.waitUntilReadStarted()

        try await link.shutdown()

        do {
            _ = try await invocation.value
            Issue.record("Expected shutdown to terminate the active invocation")
        } catch {
            #expect(error is CancellationError)
        }
        #expect(await channel.closeCount == 1)
    }

    @Test("Session and channel cleanup start concurrently", .timeLimit(.minutes(1)))
    func parentAndChildCleanupDoNotDeadlock() async throws {
        let interlock = CleanupInterlock()
        let backend = InterlockedShutdownBackend(interlock: interlock)
        let link = PeerConnectivitySymbioLink(
            session: PeerConnectivitySession(backend: backend)
        )
        try await link.start()
        let peer = remotePeer()
        await backend.emit(.peerConnected(peer))
        _ = try await link.receive()

        let channel = InterlockedCleanupChannel(
            peer: peer,
            protocolID: PeerConnectivitySymbioLink.defaultInvocationProtocolID,
            interlock: interlock
        )
        await backend.setNextChannel(channel)
        let envelope = SymbioInvocationEnvelope(
            senderID: "runtime.local",
            recipientID: "participant.remote",
            capability: "test.echo",
            representation: .typedPayload(schema: "test.echo"),
            arguments: OwnedBytes(consuming: Array("payload".utf8)),
            executionBudget: .seconds(60)
        )
        let invocation = Task {
            try await link.invoke(
                envelope,
                on: "transport.remote",
                timeout: .seconds(60)
            )
        }
        await channel.waitUntilReadStarted()

        try await link.shutdown()

        do {
            _ = try await invocation.value
            Issue.record("Expected cleanup to terminate the invocation")
        } catch is CancellationError {
            // Expected after the owned channel is closed.
        } catch {
            Issue.record("Unexpected invocation failure: \(error)")
        }
        #expect(await interlock.didStartBothSides)
        #expect(await channel.closeCount == 1)
    }

    @Test("Concurrent shutdown survives caller cancellation", .timeLimit(.minutes(1)))
    func concurrentShutdownIsOwnedByTheLink() async throws {
        let backend = MockPeerConnectivityBackend(blocksShutdown: true)
        let link = PeerConnectivitySymbioLink(
            session: PeerConnectivitySession(backend: backend)
        )
        try await link.start()

        let first = Task {
            try await link.shutdown()
        }
        await backend.waitUntilShutdownStarted()
        let second = Task {
            try await link.shutdown()
        }
        first.cancel()
        await backend.releaseShutdown()

        try await first.value
        try await second.value
        #expect(await backend.shutdownCount == 1)
        let observedCancellation = await backend.shutdownObservedCancellation
        #expect(!observedCancellation)
    }

    @Test("Admitted replies drain when new-operation capacity is full", .timeLimit(.minutes(1)))
    func admittedReplyBypassesNewOperationCapacity() async throws {
        let backend = MockPeerConnectivityBackend()
        let link = PeerConnectivitySymbioLink(
            session: PeerConnectivitySession(backend: backend),
            maximumConcurrentOperations: 1
        )
        try await link.start()
        let peer = remotePeer()
        await backend.emit(.peerConnected(peer))
        _ = try await link.receive()

        let outboundChannel = BlockingPeerConnectivityChannel(
            peer: peer,
            protocolID: PeerConnectivitySymbioLink.defaultInvocationProtocolID
        )
        await backend.setNextChannel(outboundChannel)
        let outboundEnvelope = SymbioInvocationEnvelope(
            senderID: "runtime.local",
            recipientID: "participant.remote",
            capability: "test.echo",
            representation: .typedPayload(schema: "test.echo"),
            arguments: OwnedBytes(consuming: Array("outbound".utf8)),
            executionBudget: .seconds(60)
        )
        let outbound = Task {
            try await link.invoke(
                outboundEnvelope,
                on: "transport.remote",
                timeout: .seconds(60)
            )
        }
        await outboundChannel.waitUntilReadStarted()

        let inboundEnvelope = SymbioInvocationEnvelope(
            senderID: "participant.remote",
            recipientID: "runtime.local",
            capability: "test.echo",
            representation: .typedPayload(schema: "test.echo"),
            arguments: OwnedBytes(consuming: Array("inbound".utf8)),
            executionBudget: .seconds(1)
        )
        let inboundChannel = MockPeerConnectivityChannel(
            peer: peer,
            protocolID: PeerConnectivitySymbioLink.defaultInvocationProtocolID,
            reads: [try encode(SymbioWireInvocationEnvelope(inboundEnvelope))]
        )
        await backend.emit(.channelOpened(inboundChannel))
        guard case .invocationReceived(_, let replyContext) = try await link.receive() else {
            Issue.record("Expected an admitted inbound invocation")
            try await link.shutdown()
            _ = await outbound.result
            return
        }

        try await link.send(
            .success(invocationID: inboundEnvelope.invocationID, result: nil),
            to: replyContext
        )
        #expect(inboundChannel.writeCount() == 1)
        #expect(inboundChannel.closeCount() == 1)

        try await link.shutdown()
        do {
            _ = try await outbound.value
            Issue.record("Expected shutdown to terminate the outbound invocation")
        } catch is CancellationError {
            // Expected when closing the owned channel cancels its read.
        } catch is PeerConnectivitySymbioError {
            // A typed link failure is also a valid terminal shutdown outcome.
        } catch {
            Issue.record("Unexpected outbound shutdown failure: \(error)")
        }
    }
}

@Suite("PeerConnectivity deadline ownership")
struct PeerConnectivityDeadlineTests {
    @Test("Completion at the absolute deadline is timed out", .timeLimit(.minutes(1)))
    func completionAtDeadlineIsTimedOut() async {
        let timer = ManualAsyncTimer()

        await #expect(throws: PeerConnectivitySymbioError.self) {
            _ = try await withPeerConnectivityDeadline(
                .nanoseconds(1),
                timer: timer,
                operation: {
                    timer.advance(to: 1)
                    return 1
                }
            )
        }
    }

    @Test("Timeout cleanup releases and drains the operation", .timeLimit(.minutes(1)))
    func timeoutCleanupIsDrained() async {
        let probe = PeerConnectivityDeadlineProbe()

        await #expect(throws: PeerConnectivitySymbioError.self) {
            _ = try await withPeerConnectivityDeadline(
                .milliseconds(1),
                onCancellation: { reason in
                    if case .timedOut = reason {
                        await probe.release()
                    }
                },
                operation: {
                    await probe.markStarted()
                    await probe.waitForRelease()
                    await probe.markFinished()
                    return 1
                }
            )
        }

        #expect(await probe.finished)
    }

    @Test("Timer failure is explicit and drains the operation", .timeLimit(.minutes(1)))
    func timerFailureIsExplicitAndDrained() async {
        let timer = FailingAsyncTimer()
        let probe = PeerConnectivityDeadlineProbe()

        await #expect(throws: PeerConnectivitySymbioError.self) {
            _ = try await withPeerConnectivityDeadline(
                .seconds(1),
                timer: timer,
                onCancellation: { reason in
                    if case .deadlineFailed = reason {
                        await probe.release()
                    }
                },
                operation: {
                    await probe.markStarted()
                    await probe.waitForRelease()
                    await probe.markFinished()
                    return 1
                }
            )
        }

        #expect(await probe.finished)
    }
}

private final class ManualAsyncTimer: AsyncTimer, Sendable {
    private static let clockIdentifier: UInt64 = 1
    private let nanoseconds = Mutex<UInt64>(0)

    func now() throws(TimeError) -> MonotonicInstant {
        MonotonicInstant(
            clockIdentifier: Self.clockIdentifier,
            nanoseconds: nanoseconds.withLock { $0 }
        )
    }

    func sleep(
        until deadline: MonotonicInstant
    ) async throws(TimeError) {
        guard deadline.clockIdentifier == Self.clockIdentifier else {
            throw .clockDomainMismatch(
                expected: Self.clockIdentifier,
                actual: deadline.clockIdentifier
            )
        }
        while nanoseconds.withLock({ $0 }) < deadline.nanoseconds {
            guard !Task.isCancelled else {
                throw .cancelled
            }
            await Task.yield()
        }
    }

    func advance(to value: UInt64) {
        nanoseconds.withLock { $0 = value }
    }
}

private struct FailingAsyncTimer: AsyncTimer, Sendable {
    private static let clockIdentifier: UInt64 = 2

    func now() throws(TimeError) -> MonotonicInstant {
        MonotonicInstant(
            clockIdentifier: Self.clockIdentifier,
            nanoseconds: 0
        )
    }

    func sleep(
        until deadline: MonotonicInstant
    ) async throws(TimeError) {
        throw .cancelled
    }
}

private enum TestBackendError: Error {
    case shutdown
    case channelClose
}

private actor PeerConnectivityDeadlineProbe {
    private var released = false
    private var releaseWaiter: CheckedContinuation<Void, Never>?
    private(set) var finished = false

    func markStarted() {}

    func waitForRelease() async {
        if released {
            return
        }
        await withCheckedContinuation { continuation in
            if released {
                continuation.resume()
            } else {
                releaseWaiter = continuation
            }
        }
    }

    func release() {
        guard !released else {
            return
        }
        released = true
        let waiter = releaseWaiter
        releaseWaiter = nil
        waiter?.resume()
    }

    func markFinished() {
        finished = true
    }
}

private actor MockPeerConnectivityBackend: PeerConnectivityBackend {
    nonisolated let capabilities: PeerConnectivityCapabilities = [.streamMultiplexing]
    nonisolated let events: AsyncStream<PeerConnectivityEvent>

    private let continuation: AsyncStream<PeerConnectivityEvent>.Continuation
    private let startError: (any Error & Sendable)?
    private let shutdownError: (any Error & Sendable)?
    private let blocksStart: Bool
    private let blocksShutdown: Bool
    private var nextChannel: (any PeerConnectivityChannel)?
    private var openedPeers: [String] = []
    private var starts = 0
    private var startContinuation: CheckedContinuation<Void, Never>?
    private var startStarted = false
    private var startWaiters: [CheckedContinuation<Void, Never>] = []
    private var shutdownContinuation: CheckedContinuation<Void, Never>?
    private var shutdownStarted = false
    private var shutdownStartWaiters: [CheckedContinuation<Void, Never>] = []
    private(set) var shutdownCount = 0
    private(set) var shutdownObservedCancellation = false

    init(
        startError: (any Error & Sendable)? = nil,
        shutdownError: (any Error & Sendable)? = nil,
        blocksStart: Bool = false,
        blocksShutdown: Bool = false
    ) {
        let pair = AsyncStream<PeerConnectivityEvent>.makeStream(
            bufferingPolicy: .bufferingOldest(64)
        )
        self.events = pair.stream
        self.continuation = pair.continuation
        self.startError = startError
        self.shutdownError = shutdownError
        self.blocksStart = blocksStart
        self.blocksShutdown = blocksShutdown
    }

    func start() async throws {
        starts += 1
        startStarted = true
        let waiters = startWaiters
        startWaiters.removeAll()
        for waiter in waiters {
            waiter.resume()
        }
        if let startError {
            throw startError
        }
        if blocksStart {
            await withCheckedContinuation { continuation in
                startContinuation = continuation
            }
        }
    }

    func shutdown() async throws {
        shutdownCount += 1
        let startup = startContinuation
        startContinuation = nil
        startup?.resume()
        shutdownStarted = true
        let waiters = shutdownStartWaiters
        shutdownStartWaiters.removeAll()
        for waiter in waiters {
            waiter.resume()
        }
        if blocksShutdown {
            await withCheckedContinuation { continuation in
                shutdownContinuation = continuation
            }
        }
        shutdownObservedCancellation = Task.isCancelled
        continuation.finish()
        if let shutdownError {
            throw shutdownError
        }
    }

    func waitUntilShutdownStarted() async {
        if shutdownStarted {
            return
        }
        await withCheckedContinuation { continuation in
            if shutdownStarted {
                continuation.resume()
            } else {
                shutdownStartWaiters.append(continuation)
            }
        }
    }

    func waitUntilStartStarted() async {
        if startStarted {
            return
        }
        await withCheckedContinuation { continuation in
            if startStarted {
                continuation.resume()
            } else {
                startWaiters.append(continuation)
            }
        }
    }

    func releaseShutdown() {
        let continuation = shutdownContinuation
        shutdownContinuation = nil
        continuation?.resume()
    }

    func connect(
        to endpoint: PeerConnectivityEndpoint
    ) async throws -> PeerConnectivityPeer {
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
        guard let nextChannel else {
            throw PeerConnectivityError.channelUnavailable
        }
        self.nextChannel = nil
        return nextChannel
    }

    func sendResource(
        _ resource: PeerResource,
        to peer: PeerConnectivityPeer
    ) async throws {}

    func setNextChannel(_ channel: any PeerConnectivityChannel) {
        nextChannel = channel
    }

    func openedPeerIDs() -> [String] {
        openedPeers
    }

    func startCount() -> Int {
        starts
    }

    func emit(_ event: PeerConnectivityEvent) {
        continuation.yield(event)
    }
}

private actor CleanupInterlock {
    private var channelCloseStarted = false
    private var sessionShutdownStarted = false
    private var channelWaiters: [CheckedContinuation<Void, Never>] = []
    private var sessionWaiters: [CheckedContinuation<Void, Never>] = []

    var didStartBothSides: Bool {
        channelCloseStarted && sessionShutdownStarted
    }

    func markChannelCloseStarted() {
        channelCloseStarted = true
        let waiters = channelWaiters
        channelWaiters.removeAll()
        for waiter in waiters {
            waiter.resume()
        }
    }

    func markSessionShutdownStarted() {
        sessionShutdownStarted = true
        let waiters = sessionWaiters
        sessionWaiters.removeAll()
        for waiter in waiters {
            waiter.resume()
        }
    }

    func waitForChannelClose() async {
        guard !channelCloseStarted else {
            return
        }
        await withCheckedContinuation { continuation in
            if channelCloseStarted {
                continuation.resume()
            } else {
                channelWaiters.append(continuation)
            }
        }
    }

    func waitForSessionShutdown() async {
        guard !sessionShutdownStarted else {
            return
        }
        await withCheckedContinuation { continuation in
            if sessionShutdownStarted {
                continuation.resume()
            } else {
                sessionWaiters.append(continuation)
            }
        }
    }
}

private actor InterlockedShutdownBackend: PeerConnectivityBackend {
    nonisolated let capabilities: PeerConnectivityCapabilities = [
        .streamMultiplexing
    ]
    nonisolated let events: AsyncStream<PeerConnectivityEvent>

    private let continuation: AsyncStream<PeerConnectivityEvent>.Continuation
    private let interlock: CleanupInterlock
    private var nextChannel: (any PeerConnectivityChannel)?

    init(interlock: CleanupInterlock) {
        let pair = AsyncStream<PeerConnectivityEvent>.makeStream(
            bufferingPolicy: .bufferingOldest(64)
        )
        self.events = pair.stream
        self.continuation = pair.continuation
        self.interlock = interlock
    }

    func start() async throws {}

    func shutdown() async throws {
        await interlock.markSessionShutdownStarted()
        await interlock.waitForChannelClose()
        continuation.finish()
    }

    func connect(
        to endpoint: PeerConnectivityEndpoint
    ) async throws -> PeerConnectivityPeer {
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
        guard let nextChannel else {
            throw PeerConnectivityError.channelUnavailable
        }
        self.nextChannel = nil
        return nextChannel
    }

    func sendResource(
        _ resource: PeerResource,
        to peer: PeerConnectivityPeer
    ) async throws {}

    func setNextChannel(_ channel: any PeerConnectivityChannel) {
        nextChannel = channel
    }

    func emit(_ event: PeerConnectivityEvent) {
        continuation.yield(event)
    }
}

private actor InterlockedCleanupChannel: PeerConnectivityChannel {
    nonisolated let peer: PeerConnectivityPeer
    nonisolated let protocolID: String?

    private let interlock: CleanupInterlock
    private var readContinuation: CheckedContinuation<ByteBuffer, any Error>?
    private var readStarted = false
    private var readStartWaiters: [CheckedContinuation<Void, Never>] = []
    private(set) var closeCount = 0

    init(
        peer: PeerConnectivityPeer,
        protocolID: String?,
        interlock: CleanupInterlock
    ) {
        self.peer = peer
        self.protocolID = protocolID
        self.interlock = interlock
    }

    func read() async throws -> ByteBuffer {
        readStarted = true
        let waiters = readStartWaiters
        readStartWaiters.removeAll()
        for waiter in waiters {
            waiter.resume()
        }
        return try await withCheckedThrowingContinuation { continuation in
            readContinuation = continuation
        }
    }

    func write(_ bytes: ByteBuffer) async throws {}

    func close() async throws {
        closeCount += 1
        await interlock.markChannelCloseStarted()
        await interlock.waitForSessionShutdown()
        let continuation = readContinuation
        readContinuation = nil
        continuation?.resume(throwing: CancellationError())
    }

    func waitUntilReadStarted() async {
        guard !readStarted else {
            return
        }
        await withCheckedContinuation { continuation in
            if readStarted {
                continuation.resume()
            } else {
                readStartWaiters.append(continuation)
            }
        }
    }
}

private final class MockPeerConnectivityChannel: PeerConnectivityChannel, Sendable {
    let peer: PeerConnectivityPeer
    let protocolID: String?

    private let state: Mutex<State>

    private struct State: Sendable {
        var reads: [ByteBuffer]
        var readCount = 0
        var writes: [ByteBuffer] = []
        var closeCount = 0
        var remainingCloseFailures: Int
    }

    init(
        peer: PeerConnectivityPeer,
        protocolID: String?,
        reads: [ByteBuffer],
        closeFailures: Int = 0
    ) {
        self.peer = peer
        self.protocolID = protocolID
        self.state = Mutex(State(
            reads: reads,
            remainingCloseFailures: closeFailures
        ))
    }

    func read() async throws -> ByteBuffer {
        try state.withLock { state in
            state.readCount += 1
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
        try state.withLock { state in
            state.closeCount += 1
            if state.remainingCloseFailures > 0 {
                state.remainingCloseFailures -= 1
                throw TestBackendError.channelClose
            }
        }
    }

    func closeCount() -> Int {
        state.withLock { $0.closeCount }
    }

    func writeCount() -> Int {
        state.withLock { $0.writes.count }
    }

    func readCount() -> Int {
        state.withLock(\.readCount)
    }

    func writtenFrames() -> [ByteBuffer] {
        state.withLock(\.writes)
    }
}

private actor BlockingPeerConnectivityChannel: PeerConnectivityChannel {
    nonisolated let peer: PeerConnectivityPeer
    nonisolated let protocolID: String?

    private var readContinuation: CheckedContinuation<ByteBuffer, any Error>?
    private var readStarted = false
    private var readStartWaiters: [CheckedContinuation<Void, Never>] = []
    private var isClosed = false
    private(set) var closeCount = 0

    init(peer: PeerConnectivityPeer, protocolID: String?) {
        self.peer = peer
        self.protocolID = protocolID
    }

    func read() async throws -> ByteBuffer {
        guard !isClosed else {
            throw CancellationError()
        }
        return try await withCheckedThrowingContinuation { continuation in
            readContinuation = continuation
            readStarted = true
            let waiters = readStartWaiters
            readStartWaiters.removeAll()
            for waiter in waiters {
                waiter.resume()
            }
        }
    }

    func write(_ bytes: ByteBuffer) async throws {}

    func close() async throws {
        closeCount += 1
        guard !isClosed else {
            return
        }
        isClosed = true
        let continuation = readContinuation
        readContinuation = nil
        continuation?.resume(throwing: CancellationError())
    }

    func waitUntilReadStarted() async {
        guard !readStarted else {
            return
        }
        await withCheckedContinuation { continuation in
            if readStarted {
                continuation.resume()
            } else {
                readStartWaiters.append(continuation)
            }
        }
    }
}

private func remotePeer() -> PeerConnectivityPeer {
    PeerConnectivityPeer(
        id: "transport.remote",
        displayName: "Remote",
        identity: .backend(kind: "test", value: "authenticated.remote")
    )
}

private func encode<Value: Encodable>(_ value: Value) throws -> ByteBuffer {
    try frame(JSONEncoder().encode(value))
}

private func frame(_ data: Data) throws -> ByteBuffer {
    try SymbioWireFrameCodec(
        maximumPayloadBytes: 4 * 1_024 * 1_024
    ).frame(data)
}

private func split(
    _ frameBuffer: ByteBuffer,
    chunkSizes: [Int]
) -> [ByteBuffer] {
    precondition(chunkSizes.allSatisfy { $0 > 0 })
    let bytes = Array(frameBuffer.readableBytesView)
    var chunks: [ByteBuffer] = []
    var offset = 0
    for requestedSize in chunkSizes where offset < bytes.count {
        let end = Swift.min(offset + requestedSize, bytes.count)
        chunks.append(buffer(from: Data(bytes[offset..<end])))
        offset = end
    }
    if offset < bytes.count {
        chunks.append(buffer(from: Data(bytes[offset...])))
    }
    return chunks
}

private func buffer(from data: Data) -> ByteBuffer {
    var buffer = ByteBuffer()
    buffer.writeBytes(data)
    return buffer
}
