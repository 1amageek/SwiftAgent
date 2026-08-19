import Foundation
import NIOCore
import NetworkingTime
import PeerConnectivity
import SwiftAgentSymbio

/// Adapts one `PeerConnectivitySession` to the transport-independent Symbio link.
///
/// The session backend must make outstanding `openChannel`, channel `read`, and
/// channel `write`, and session `start` calls return when either the channel is
/// closed or the session is shut down. This cancellation contract is required
/// for bounded deadlines and deterministic link shutdown.
public actor PeerConnectivitySymbioLink: SymbioLink {
    public static let defaultInvocationProtocolID = "/swiftagent/symbio/invoke/2.0.0"
    public static let defaultAnnouncementProtocolID = "/swiftagent/symbio/announce/2.0.0"

    private enum State {
        case idle
        case starting
        case running
        case stopping
        case cleanupFailed(PeerConnectivitySymbioError)
        case finished(PeerConnectivitySymbioError?)
    }

    private enum StopCause {
        case requested
        case failure(PeerConnectivitySymbioError)
    }

    private struct PendingReply {
        let peerID: TransportPeerID
        let peerGeneration: UInt64
        let invocationID: String
        let channel: PeerConnectivityOwnedChannel
    }

    private struct ReconciliationTask {
        let id: String
        let peerGeneration: UInt64
        let task: Task<Void, Never>
    }

    private struct CleanupResult {
        let failures: [String]
        let hasPendingResources: Bool
    }

    private enum ResourceCleanupOutcome: Sendable {
        case channel(PeerConnectivityOwnedChannel, failure: String?)
        case session(failure: String?)
    }

    private let session: PeerConnectivitySession
    private let sessionOwner: PeerConnectivityOwnedSession
    private let invocationProtocolID: String
    private let announcementProtocolID: String
    private let eventCapacity: Int
    private let maximumPendingChannels: Int
    private let maximumPendingReplies: Int
    private let maximumConcurrentOperations: Int
    private let wireCodec: SymbioWireFrameCodec
    private let channelOperationTimeout: Duration
    private let timer: any AsyncTimer

    private var state = State.idle
    private var stopCause: StopCause?
    private var startupFailure: PeerConnectivitySymbioError?
    private var eventTask: Task<Void, Never>?
    private var cleanupTask: Task<Void, Never>?
    private var channelTasks: [String: Task<Void, Never>] = [:]
    private var peers: [TransportPeerID: PeerConnectivityPeer] = [:]
    private var peerGenerations: [TransportPeerID: UInt64] = [:]
    private var publishedDescriptors: [ParticipantID: ParticipantDescriptor] = [:]
    private var catalogRevision: UInt64 = 0
    private var announcedDescriptors: [
        TransportPeerID: [ParticipantID: ParticipantDescriptor]
    ] = [:]
    private var reconciliationTasks: [TransportPeerID: ReconciliationTask] = [:]
    private var retiredReconciliationTasks: [String: Task<Void, Never>] = [:]
    private var pendingReplies: [String: PendingReply] = [:]
    private var ownedChannels: [String: PeerConnectivityOwnedChannel] = [:]
    private var sessionShutdownPending = false
    private var queuedEvents: [SymbioLinkEvent] = []
    private var receiver: CheckedContinuation<SymbioLinkEvent?, any Error>?
    private var activeIOCount = 0
    private var activeReplyCount = 0
    private var ioDrainWaiters: [CheckedContinuation<Void, Never>] = []

    public init(
        session: PeerConnectivitySession,
        invocationProtocolID: String = PeerConnectivitySymbioLink.defaultInvocationProtocolID,
        announcementProtocolID: String = PeerConnectivitySymbioLink.defaultAnnouncementProtocolID,
        eventCapacity: Int = 256,
        maximumPendingChannels: Int = 512,
        maximumPendingReplies: Int = 256,
        maximumConcurrentOperations: Int = 256,
        maximumWireMessageBytes: Int = 4 * 1_024 * 1_024,
        channelOperationTimeout: Duration = .seconds(30),
        timer: any AsyncTimer = ContinuousAsyncTimer()
    ) {
        self.session = session
        self.sessionOwner = PeerConnectivityOwnedSession(session)
        self.invocationProtocolID = invocationProtocolID
        self.announcementProtocolID = announcementProtocolID
        self.eventCapacity = eventCapacity
        self.maximumPendingChannels = maximumPendingChannels
        self.maximumPendingReplies = maximumPendingReplies
        self.maximumConcurrentOperations = maximumConcurrentOperations
        self.wireCodec = SymbioWireFrameCodec(
            maximumPayloadBytes: maximumWireMessageBytes
        )
        self.channelOperationTimeout = channelOperationTimeout
        self.timer = timer
    }

    public func start() async throws {
        guard case .idle = state else {
            throw PeerConnectivitySymbioError.invalidLifecycle(
                "The link can only be started once"
            )
        }
        try validateConfiguration()
        try session.require(.streamMultiplexing)

        let events = session.subscribe()
        state = .starting
        eventTask = Task { [weak self] in
            for await event in events {
                guard !Task.isCancelled else {
                    return
                }
                guard await self?.consume(event) == true else {
                    return
                }
            }
            await self?.backendEventStreamEnded()
        }

        do {
            sessionShutdownPending = true
            let sessionOwner = self.sessionOwner
            let session = self.session
            try await withPeerConnectivityDeadline(
                channelOperationTimeout,
                timer: timer,
                onCancellation: { _ in
                    try await sessionOwner.shutdown()
                },
                operation: {
                    try await session.start()
                }
            )
            guard case .starting = state else {
                throw startupFailure ?? PeerConnectivitySymbioError.invalidLifecycle(
                    "The backend ended while it was starting"
                )
            }
            state = .running
        } catch {
            let originalFailure = error.localizedDescription
            state = .stopping
            let task = eventTask
            eventTask = nil
            task?.cancel()
            let ownedTasks = beginResourceCleanup()
            _ = await completeResourceCleanup()
            for ownedTask in ownedTasks {
                await ownedTask.value
            }
            await task?.value
            let cleanup = await completeResourceCleanup()
            if error is CancellationError,
               Task.isCancelled,
               cleanup.failures.isEmpty {
                finish(with: nil, cleanupPending: cleanup.hasPendingResources)
                throw CancellationError()
            }
            let terminal: PeerConnectivitySymbioError
            if cleanup.failures.isEmpty,
               let typedError = error as? PeerConnectivitySymbioError {
                terminal = typedError
            } else if cleanup.failures.isEmpty {
                terminal = .backendFailed(originalFailure)
            } else {
                terminal = .cleanupFailed(
                    [originalFailure] + cleanup.failures
                )
            }
            finish(
                with: terminal,
                cleanupPending: cleanup.hasPendingResources
            )
            throw terminal
        }
    }

    public func synchronizeLocalParticipants(
        _ descriptors: [ParticipantDescriptor]
    ) async throws {
        guard acceptsPublication else {
            throw PeerConnectivitySymbioError.invalidLifecycle(
                "The link no longer accepts participant publications"
            )
        }
        let identifiers = descriptors.map(\.id)
        guard Set(identifiers).count == identifiers.count else {
            throw PeerConnectivitySymbioError.invalidLocalCatalog(
                "Participant identifiers must be unique"
            )
        }
        for descriptor in descriptors {
            _ = try encode(
                SymbioWireAnnouncement.publish(descriptor).validated()
            )
        }
        publishedDescriptors = Dictionary(
            uniqueKeysWithValues: descriptors.map { ($0.id, $0) }
        )
        catalogRevision &+= 1
        guard case .running = state else {
            return
        }
        for peerID in Array(peers.keys) {
            scheduleReconciliation(for: peerID)
        }
    }

    public func receive() async throws -> SymbioLinkEvent? {
        if !queuedEvents.isEmpty {
            return queuedEvents.removeFirst()
        }
        switch state {
        case .starting, .running:
            guard receiver == nil else {
                throw PeerConnectivitySymbioError.concurrentReceive
            }
            return try await withCheckedThrowingContinuation { continuation in
                receiver = continuation
            }
        case .finished(let error):
            if let error {
                throw error
            }
            return nil
        case .cleanupFailed(let error):
            throw error
        case .idle, .stopping:
            throw PeerConnectivitySymbioError.invalidLifecycle(
                "The link is not receiving events"
            )
        }
    }

    public func invoke(
        _ envelope: SymbioInvocationEnvelope,
        on transportPeerID: TransportPeerID,
        timeout: Duration
    ) async throws -> SymbioInvocationReply {
        guard case .running = state else {
            throw PeerConnectivitySymbioError.invalidLifecycle(
                "The link must be running before invocation"
            )
        }
        guard let peer = peers[transportPeerID],
              let peerGeneration = peerGenerations[transportPeerID] else {
            throw PeerConnectivitySymbioError.peerUnavailable(transportPeerID)
        }
        try beginIO()
        defer { endIO() }

        let request = try encode(
            SymbioWireInvocationEnvelope(envelope).validated()
        )
        let session = self.session
        let protocolID = invocationProtocolID
        let wireCodec = self.wireCodec
        let channelSlot = PeerConnectivityOwnedChannelSlot()

        do {
            return try await withPeerConnectivityDeadline(
                timeout,
                timer: timer,
                onCancellation: { _ in
                    try await self.cancelChannelAcquisition(
                        channelSlot,
                        operation: "outbound invocation"
                    )
                }
            ) {
                let channel = PeerConnectivityOwnedChannel(
                    try await session.openStream(
                        named: protocolID,
                        to: peer
                    )
                )
                channelSlot.store(channel)
                let reply: SymbioInvocationReply
                do {
                    try Self.validateOpenedChannel(
                        channel.value,
                        expectedPeer: peer,
                        expectedProtocolID: protocolID
                    )
                    try await self.retainOwnedChannel(channel)
                    try await self.validateCurrentPeer(
                        peer,
                        generation: peerGeneration
                    )
                    try Task.checkCancellation()
                    try await channel.value.write(request)
                    let replyData = try await wireCodec.readFrame(
                        from: channel.value
                    )
                    let wireReply = try Self.decode(
                        SymbioWireInvocationReply.self,
                        from: replyData
                    )
                    reply = try wireReply.value()
                    guard reply.invocationID == envelope.invocationID else {
                        throw PeerConnectivitySymbioError.invalidWireMessage(
                            "Reply invocation ID did not match its request"
                        )
                    }
                    try await self.validateCurrentPeer(
                        peer,
                        generation: peerGeneration
                    )
                } catch {
                    let operationFailure = error.localizedDescription
                    do {
                        try await self.closeOwned(channel)
                    } catch {
                        channelSlot.clear(channel.id)
                        throw PeerConnectivitySymbioError.cleanupFailed([
                            operationFailure,
                            error.localizedDescription,
                        ])
                    }
                    channelSlot.clear(channel.id)
                    throw error
                }
                try await self.closeOwned(channel)
                channelSlot.clear(channel.id)
                return reply
            }
        } catch is CancellationError {
            throw cancellationError(
                unexpectedMessage: "Outbound invocation cancelled without caller cancellation"
            )
        } catch let error as PeerConnectivitySymbioError {
            throw error
        } catch {
            throw PeerConnectivitySymbioError.backendFailed(
                error.localizedDescription
            )
        }
    }

    public func send(
        _ reply: SymbioInvocationReply,
        to context: SymbioReplyContext
    ) async throws {
        guard let pending = pendingReplies[context.id],
              pending.peerID == context.transportPeerID else {
            throw PeerConnectivitySymbioError.replyContextUnavailable(context.id)
        }
        pendingReplies.removeValue(forKey: context.id)
        do {
            try beginAdmittedReplyIO()
        } catch {
            let lifecycleFailure = error
            do {
                try await closeOwned(pending.channel)
            } catch {
                throw PeerConnectivitySymbioError.cleanupFailed([
                    lifecycleFailure.localizedDescription,
                    error.localizedDescription,
                ])
            }
            throw lifecycleFailure
        }
        defer { endAdmittedReplyIO() }
        do {
            guard reply.invocationID == pending.invocationID else {
                throw PeerConnectivitySymbioError.invalidWireMessage(
                    "Reply invocation ID did not match its reply context"
                )
            }
            try validateCurrentPeer(
                pending.peerID,
                generation: pending.peerGeneration
            )
        } catch {
            let validationFailure = error
            do {
                try await closeOwned(pending.channel)
            } catch {
                throw PeerConnectivitySymbioError.cleanupFailed([
                    validationFailure.localizedDescription,
                    error.localizedDescription,
                ])
            }
            throw validationFailure
        }
        let frame: ByteBuffer
        do {
            frame = try encode(SymbioWireInvocationReply(reply).validated())
        } catch {
            let encodingFailure = error
            do {
                try await closeOwned(pending.channel)
            } catch {
                throw PeerConnectivitySymbioError.cleanupFailed([
                    encodingFailure.localizedDescription,
                    error.localizedDescription,
                ])
            }
            throw encodingFailure
        }
        do {
            try await performChannelOperation(on: pending.channel) {
                try await pending.channel.value.write(frame)
            }
        } catch {
            let operationFailure = error.localizedDescription
            do {
                try await closeOwned(pending.channel)
            } catch {
                throw PeerConnectivitySymbioError.cleanupFailed([
                    operationFailure,
                    error.localizedDescription,
                ])
            }
            throw error
        }
        try await closeOwned(pending.channel)
    }

    public func shutdown() async throws {
        if case .stopping = state, let cleanupTask {
            await cleanupTask.value
            try throwCleanupFailureIfPresent()
            return
        }
        switch state {
        case .finished:
            return
        case .cleanupFailed:
            stopCause = .requested
            state = .stopping
        case .stopping:
            throw PeerConnectivitySymbioError.invalidLifecycle(
                "Link startup cleanup is already in progress"
            )
        case .starting:
            throw PeerConnectivitySymbioError.invalidLifecycle(
                "Link startup is still in progress"
            )
        case .idle, .running:
            stopCause = .requested
            state = .stopping
        }

        let task = eventTask
        eventTask = nil
        task?.cancel()
        let ownedTasks = beginResourceCleanup()
        let cleanupTask = Task { [self] in
            _ = await completeResourceCleanup()
            await waitForIODrain()
            for ownedTask in ownedTasks {
                await ownedTask.value
            }
            await task?.value
            let cleanup = await completeResourceCleanup()

            if cleanup.failures.isEmpty {
                finish(with: nil, cleanupPending: false)
            } else {
                let error = PeerConnectivitySymbioError.cleanupFailed(
                    cleanup.failures
                )
                finish(
                    with: error,
                    cleanupPending: true
                )
            }
            self.cleanupTask = nil
        }
        self.cleanupTask = cleanupTask
        await cleanupTask.value
        try throwCleanupFailureIfPresent()
    }

    private var acceptsPublication: Bool {
        switch state {
        case .idle, .starting, .running:
            return true
        case .stopping, .cleanupFailed, .finished:
            return false
        }
    }

    private func consume(_ event: PeerConnectivityEvent) async -> Bool {
        guard acceptsEvents else {
            if case .channelOpened(let channelValue) = event {
                let channel = PeerConnectivityOwnedChannel(channelValue)
                ownedChannels[channel.id] = channel
                do {
                    try await closeOwned(channel)
                } catch {
                    ownedChannels[channel.id] = channel
                }
            }
            return false
        }
        switch event {
        case .peerDiscovered:
            return true
        case .peerLost(let peer), .peerDisconnected(let peer):
            let peerID: TransportPeerID
            do {
                peerID = try Self.validatedTransportPeerID(for: peer)
            } catch {
                await terminateUnexpectedly(.backendFailed(
                    error.localizedDescription
                ))
                return false
            }
            guard let currentPeer = peers[peerID],
                  Self.hasSameTransportIdentity(currentPeer, peer) else {
                return await enqueueOrFail(.diagnostic(
                    "Ignored a stale disconnect event for peer "
                        + "'\(peerID.rawValue)'"
                ))
            }
            peers.removeValue(forKey: peerID)
            peerGenerations[peerID, default: 0] &+= 1
            cancelReconciliation(for: peerID)
            announcedDescriptors.removeValue(forKey: peerID)
            await discardPendingReplies(for: peerID)
            return await enqueueOrFail(.peerDisconnected(peerID))
        case .peerConnected(let peer):
            let peerID: TransportPeerID
            do {
                peerID = try Self.validatedTransportPeerID(for: peer)
            } catch {
                await terminateUnexpectedly(.backendFailed(
                    error.localizedDescription
                ))
                return false
            }
            if let currentPeer = peers[peerID],
               Self.hasSameTransportIdentity(currentPeer, peer) {
                peers[peerID] = peer
                return true
            }
            if peers[peerID] != nil {
                cancelReconciliation(for: peerID)
                announcedDescriptors.removeValue(forKey: peerID)
                await discardPendingReplies(for: peerID)
                guard await enqueueOrFail(.peerDisconnected(peerID)) else {
                    return false
                }
            }
            cancelReconciliation(for: peerID)
            peers[peerID] = peer
            peerGenerations[peerID, default: 0] &+= 1
            announcedDescriptors[peerID] = [:]
            guard await enqueueOrFail(.peerConnected(peerID)) else {
                return false
            }
            scheduleReconciliation(for: peerID)
            return true
        case .channelOpened(let channel):
            let peerID: TransportPeerID
            do {
                peerID = try Self.validatedTransportPeerID(for: channel.peer)
            } catch {
                return await rejectInboundChannel(
                    channel,
                    reason: error.localizedDescription
                )
            }
            guard let peer = peers[peerID],
                  peer.identity == channel.peer.identity,
                  let peerGeneration = peerGenerations[peerID] else {
                return await rejectInboundChannel(
                    channel,
                    reason: "Inbound channel was not bound to the current peer connection"
                )
            }
            guard channelTasks.count < maximumPendingChannels else {
                return await rejectInboundChannel(
                    channel,
                    reason: "Inbound channel capacity was exceeded"
                )
            }
            schedule(
                channel,
                peer: peer,
                peerID: peerID,
                peerGeneration: peerGeneration
            )
            return true
        case .messageReceived, .resourceReceived:
            return true
        case .error(let event):
            let peerDescription = event.peer.map { " for peer '\($0.id)'" } ?? ""
            return await enqueueOrFail(.diagnostic(
                "PeerConnectivity operation '\(event.operation)' failed"
                    + peerDescription
                    + ": \(event.error.localizedDescription)"
            ))
        }
    }

    private func schedule(
        _ channelValue: any PeerConnectivityChannel,
        peer: PeerConnectivityPeer,
        peerID: TransportPeerID,
        peerGeneration: UInt64
    ) {
        let channel = PeerConnectivityOwnedChannel(channelValue)
        ownedChannels[channel.id] = channel
        let taskID = UUID().uuidString
        let task: Task<Void, Never>
        if channel.value.protocolID == invocationProtocolID {
            task = Task { [weak self] in
                await self?.receiveInvocation(
                    from: channel,
                    peer: peer,
                    peerID: peerID,
                    peerGeneration: peerGeneration,
                    taskID: taskID
                )
            }
        } else if channel.value.protocolID == announcementProtocolID {
            task = Task { [weak self] in
                await self?.receiveAnnouncement(
                    from: channel,
                    peer: peer,
                    peerID: peerID,
                    peerGeneration: peerGeneration,
                    taskID: taskID
                )
            }
        } else {
            task = Task {
                do {
                    try await self.closeOwned(channel)
                } catch {
                    await self.recordChannelDiagnostic(
                        "Failed to close unsupported protocol channel: "
                            + error.localizedDescription
                    )
                }
                self.channelTaskFinished(taskID)
            }
        }
        channelTasks[taskID] = task
    }

    private func rejectInboundChannel(
        _ channelValue: any PeerConnectivityChannel,
        reason: String
    ) async -> Bool {
        let channel = PeerConnectivityOwnedChannel(channelValue)
        ownedChannels[channel.id] = channel
        var diagnostic = "Rejected inbound channel: \(reason)"
        do {
            try await closeOwned(channel)
        } catch {
            diagnostic += "; cleanup failed: \(error.localizedDescription)"
        }
        return await enqueueOrFail(.diagnostic(diagnostic))
    }

    private func receiveAnnouncement(
        from channel: PeerConnectivityOwnedChannel,
        peer: PeerConnectivityPeer,
        peerID: TransportPeerID,
        peerGeneration: UInt64,
        taskID: String
    ) async {
        var event: SymbioLinkEvent?
        var diagnostics: [String] = []
        do {
            let wireCodec = self.wireCodec
            let data = try await performChannelOperation(on: channel) {
                try await wireCodec.readFrame(from: channel.value)
            }
            let announcement = try Self.decode(
                SymbioWireAnnouncement.self,
                from: data
            ).validated()
            try validateCurrentPeer(peer, generation: peerGeneration)
            switch announcement.operation {
            case .publish:
                guard let descriptor = announcement.descriptor else {
                    throw PeerConnectivitySymbioError.invalidWireMessage(
                        "Publish announcement is missing its descriptor"
                    )
                }
                event = .peerClaimed(SymbioPeerClaim(
                    transportPeerID: peerID,
                    descriptor: descriptor,
                    authentication: Self.authentication(for: peer)
                ))
            case .withdraw:
                guard let participantID = announcement.participantID else {
                    throw PeerConnectivitySymbioError.invalidWireMessage(
                        "Withdraw announcement is missing its participant ID"
                    )
                }
                event = .participantWithdrawn(participantID, from: peerID)
            }
        } catch {
            diagnostics.append(
                "Failed to receive participant announcement from peer "
                + "'\(channel.value.peer.id)': \(error.localizedDescription)"
            )
        }
        do {
            try await closeOwned(channel)
        } catch {
            diagnostics.append(
                "Failed to close announcement channel: "
                    + error.localizedDescription
            )
        }
        if let event {
            _ = await enqueueOrFail(event)
        }
        for diagnostic in diagnostics {
            await recordChannelDiagnostic(diagnostic)
        }
        channelTaskFinished(taskID)
    }

    private func receiveInvocation(
        from channel: PeerConnectivityOwnedChannel,
        peer: PeerConnectivityPeer,
        peerID: TransportPeerID,
        peerGeneration: UInt64,
        taskID: String
    ) async {
        var transferredToPendingReply = false
        var diagnostics: [String] = []
        do {
            let wireCodec = self.wireCodec
            let data = try await performChannelOperation(on: channel) {
                try await wireCodec.readFrame(from: channel.value)
            }
            let envelope = try Self.decode(
                SymbioWireInvocationEnvelope.self,
                from: data
            ).value()
            try validateCurrentPeer(peer, generation: peerGeneration)
            if pendingReplies.count + activeReplyCount
                >= maximumPendingReplies {
                try await sendOverloadedReply(
                    invocationID: envelope.invocationID,
                    on: channel
                )
            } else {
                let context = SymbioReplyContext(
                    id: UUID().uuidString,
                    transportPeerID: peerID
                )
                pendingReplies[context.id] = PendingReply(
                    peerID: peerID,
                    peerGeneration: peerGeneration,
                    invocationID: envelope.invocationID,
                    channel: channel
                )
                if enqueue(.invocationReceived(
                    envelope: envelope,
                    replyContext: context
                )) {
                    transferredToPendingReply = true
                } else {
                    pendingReplies.removeValue(forKey: context.id)
                    try await sendOverloadedReply(
                        invocationID: envelope.invocationID,
                        on: channel
                    )
                }
            }
        } catch {
            diagnostics.append(
                "Failed to receive invocation from peer "
                + "'\(channel.value.peer.id)': \(error.localizedDescription)"
            )
        }
        if !transferredToPendingReply {
            do {
                try await closeOwned(channel)
            } catch {
                diagnostics.append(
                    "Failed to close invocation channel: "
                        + error.localizedDescription
                )
            }
        }
        for diagnostic in diagnostics {
            await recordChannelDiagnostic(diagnostic)
        }
        channelTaskFinished(taskID)
    }

    private func sendOverloadedReply(
        invocationID: String,
        on channel: PeerConnectivityOwnedChannel
    ) async throws {
        let reply = SymbioInvocationReply.failure(
            invocationID: invocationID,
            code: .overloaded,
            message: "Receiver is at capacity"
        )
        let frame = try encode(SymbioWireInvocationReply(reply).validated())
        try await performChannelOperation(on: channel) {
            try await channel.value.write(frame)
        }
    }

    private func scheduleReconciliation(for peerID: TransportPeerID) {
        guard reconciliationTasks[peerID] == nil,
              peers[peerID] != nil,
              let peerGeneration = peerGenerations[peerID],
              case .running = state else {
            return
        }
        let taskID = UUID().uuidString
        let task = Task { [weak self] in
            guard let self else {
                return
            }
            await self.reconcileLocalParticipants(
                with: peerID,
                peerGeneration: peerGeneration,
                taskID: taskID
            )
        }
        reconciliationTasks[peerID] = ReconciliationTask(
            id: taskID,
            peerGeneration: peerGeneration,
            task: task
        )
    }

    private func cancelReconciliation(for peerID: TransportPeerID) {
        let reconciliation = reconciliationTasks.removeValue(forKey: peerID)
        guard let reconciliation else {
            return
        }
        retiredReconciliationTasks[reconciliation.id] = reconciliation.task
        reconciliation.task.cancel()
    }

    private func reconcileLocalParticipants(
        with peerID: TransportPeerID,
        peerGeneration: UInt64,
        taskID: String
    ) async {
        var retryDelay = Duration.milliseconds(100)
        while !Task.isCancelled {
            guard case .running = state,
                  peerGenerations[peerID] == peerGeneration,
                  let peer = peers[peerID] else {
                finishReconciliation(
                    for: peerID,
                    peerGeneration: peerGeneration,
                    taskID: taskID
                )
                return
            }

            let revision = catalogRevision
            let desired = publishedDescriptors
            let announced = announcedDescriptors[peerID] ?? [:]
            do {
                let withdrawnIDs = Set(announced.keys)
                    .subtracting(desired.keys)
                    .sorted { $0.rawValue < $1.rawValue }
                for participantID in withdrawnIDs {
                    try Task.checkCancellation()
                    try await sendReconciliationAnnouncement(
                        .withdraw(participantID),
                        to: peer,
                        peerGeneration: peerGeneration
                    )
                    guard peerGenerations[peerID] == peerGeneration else {
                        throw CancellationError()
                    }
                    announcedDescriptors[peerID]?.removeValue(
                        forKey: participantID
                    )
                }

                let changedDescriptors = desired.values.filter {
                    announced[$0.id] != $0
                }.sorted { $0.id.rawValue < $1.id.rawValue }
                for descriptor in changedDescriptors {
                    try Task.checkCancellation()
                    try await sendReconciliationAnnouncement(
                        .publish(descriptor),
                        to: peer,
                        peerGeneration: peerGeneration
                    )
                    guard peerGenerations[peerID] == peerGeneration else {
                        throw CancellationError()
                    }
                    announcedDescriptors[peerID, default: [:]][descriptor.id]
                        = descriptor
                }

                if revision == catalogRevision {
                    finishReconciliation(
                        for: peerID,
                        peerGeneration: peerGeneration,
                        taskID: taskID
                    )
                    return
                }
                retryDelay = .milliseconds(100)
            } catch is CancellationError {
                finishReconciliation(
                    for: peerID,
                    peerGeneration: peerGeneration,
                    taskID: taskID
                )
                return
            } catch {
                guard await enqueueOrFail(.diagnostic(
                    "Failed to reconcile local participants with peer "
                        + "'\(peer.id)': \(error.localizedDescription)"
                )) else {
                    finishReconciliation(
                        for: peerID,
                        peerGeneration: peerGeneration,
                        taskID: taskID
                    )
                    return
                }
                do {
                    try await Task.sleep(for: retryDelay)
                } catch {
                    finishReconciliation(
                        for: peerID,
                        peerGeneration: peerGeneration,
                        taskID: taskID
                    )
                    return
                }
                retryDelay = Swift.min(
                    retryDelay + retryDelay,
                    .seconds(5)
                )
            }
        }
        finishReconciliation(
            for: peerID,
            peerGeneration: peerGeneration,
            taskID: taskID
        )
    }

    private func finishReconciliation(
        for peerID: TransportPeerID,
        peerGeneration: UInt64,
        taskID: String
    ) {
        if reconciliationTasks[peerID]?.peerGeneration == peerGeneration,
           reconciliationTasks[peerID]?.id == taskID {
            reconciliationTasks.removeValue(forKey: peerID)
        }
        retiredReconciliationTasks.removeValue(forKey: taskID)
    }

    private func sendAnnouncement(
        _ announcement: SymbioWireAnnouncement,
        to peer: PeerConnectivityPeer,
        peerGeneration: UInt64
    ) async throws {
        let frame = try encode(announcement.validated())
        let session = self.session
        let protocolID = announcementProtocolID
        let channelSlot = PeerConnectivityOwnedChannelSlot()
        try await withPeerConnectivityDeadline(
            channelOperationTimeout,
            timer: timer,
            onCancellation: { _ in
                try await self.cancelChannelAcquisition(
                    channelSlot,
                    operation: "participant announcement"
                )
            }
        ) {
            let channel = PeerConnectivityOwnedChannel(
                try await session.openStream(named: protocolID, to: peer)
            )
            channelSlot.store(channel)
            do {
                try Self.validateOpenedChannel(
                    channel.value,
                    expectedPeer: peer,
                    expectedProtocolID: protocolID
                )
                try await self.retainOwnedChannel(channel)
                try await self.validateCurrentPeer(
                    peer,
                    generation: peerGeneration
                )
                try Task.checkCancellation()
                try await channel.value.write(frame)
            } catch {
                let operationFailure = error.localizedDescription
                do {
                    try await self.closeOwned(channel)
                } catch {
                    channelSlot.clear(channel.id)
                    throw PeerConnectivitySymbioError.cleanupFailed([
                        operationFailure,
                        error.localizedDescription,
                    ])
                }
                channelSlot.clear(channel.id)
                throw error
            }
            try await self.closeOwned(channel)
            channelSlot.clear(channel.id)
        }
    }

    private func sendReconciliationAnnouncement(
        _ announcement: SymbioWireAnnouncement,
        to peer: PeerConnectivityPeer,
        peerGeneration: UInt64
    ) async throws {
        try beginIO()
        defer { endIO() }
        try await sendAnnouncement(
            announcement,
            to: peer,
            peerGeneration: peerGeneration
        )
    }

    private func encode<Value: Encodable>(_ value: Value) throws -> ByteBuffer {
        let data: Data
        do {
            data = try JSONEncoder().encode(value)
        } catch {
            throw PeerConnectivitySymbioError.invalidWireMessage(
                "JSON encoding failed: \(error.localizedDescription)"
            )
        }
        return try wireCodec.frame(data)
    }

    private static func decode<Value: Decodable>(
        _ type: Value.Type,
        from data: Data
    ) throws -> Value {
        do {
            return try JSONDecoder().decode(type, from: data)
        } catch {
            throw PeerConnectivitySymbioError.invalidWireMessage(
                "JSON decoding failed: \(error.localizedDescription)"
            )
        }
    }

    private func enqueue(_ event: SymbioLinkEvent) -> Bool {
        guard acceptsEvents else {
            return false
        }
        if let receiver {
            self.receiver = nil
            receiver.resume(returning: event)
            return true
        }
        guard queuedEvents.count < eventCapacity else {
            return false
        }
        queuedEvents.append(event)
        return true
    }

    private func enqueueOrFail(_ event: SymbioLinkEvent) async -> Bool {
        guard enqueue(event) else {
            await terminateUnexpectedly(
                PeerConnectivitySymbioError.eventBufferFull(eventCapacity)
            )
            return false
        }
        return true
    }

    private var acceptsEvents: Bool {
        switch state {
        case .starting, .running:
            return true
        case .idle, .stopping, .cleanupFailed, .finished:
            return false
        }
    }

    private func recordChannelDiagnostic(_ message: String) async {
        _ = await enqueueOrFail(.diagnostic(message))
    }

    private func channelTaskFinished(_ id: String) {
        channelTasks.removeValue(forKey: id)
    }

    private func discardPendingReplies(for peerID: TransportPeerID) async {
        let entries = pendingReplies.filter { $0.value.peerID == peerID }
        for (id, pending) in entries {
            pendingReplies.removeValue(forKey: id)
            do {
                try await closeOwned(pending.channel)
            } catch {
                await recordChannelDiagnostic(
                    "Failed to close reply channel for disconnected peer "
                        + "'\(peerID.rawValue)': \(error.localizedDescription)"
                )
            }
        }
    }

    private func backendEventStreamEnded() async {
        switch state {
        case .starting:
            startupFailure = .backendFailed(
                "The backend event stream ended while the link was starting"
            )
            state = .stopping
        case .running:
            await terminateUnexpectedly(.backendFailed(
                "The backend event stream ended while the link was running"
            ))
        case .idle, .stopping, .cleanupFailed, .finished:
            break
        }
    }

    private func terminateUnexpectedly(
        _ terminalError: PeerConnectivitySymbioError
    ) async {
        switch state {
        case .starting:
            stopCause = .failure(terminalError)
            startupFailure = terminalError
            state = .stopping
            return
        case .running:
            stopCause = .failure(terminalError)
            state = .stopping
        case .idle, .stopping, .cleanupFailed, .finished:
            return
        }
        eventTask?.cancel()
        eventTask = nil
        let ownedTasks = beginResourceCleanup()
        cleanupTask = Task {
            _ = await self.completeResourceCleanup()
            await self.waitForIODrain()
            for ownedTask in ownedTasks {
                await ownedTask.value
            }
            await self.finishUnexpectedShutdown(with: terminalError)
        }
    }

    private func beginResourceCleanup() -> [Task<Void, Never>] {
        let tasks = Array(channelTasks.values)
            + reconciliationTasks.values.map(\.task)
            + Array(retiredReconciliationTasks.values)
        channelTasks.removeAll()
        reconciliationTasks.removeAll()
        retiredReconciliationTasks.removeAll()
        for task in tasks {
            task.cancel()
        }
        return tasks
    }

    private func completeResourceCleanup() async -> CleanupResult {
        var failures: [String] = []
        pendingReplies.removeAll()
        let channels = ownedChannels.values.sorted { $0.id < $1.id }
        let shouldShutdownSession = sessionShutdownPending
        let sessionOwner = self.sessionOwner
        await withTaskGroup(of: ResourceCleanupOutcome.self) { group in
            for channel in channels {
                group.addTask {
                    do {
                        try await channel.close()
                        return .channel(channel, failure: nil)
                    } catch {
                        return .channel(
                            channel,
                            failure: error.localizedDescription
                        )
                    }
                }
            }
            if shouldShutdownSession {
                group.addTask {
                    do {
                        try await sessionOwner.shutdown()
                        return .session(failure: nil)
                    } catch {
                        return .session(
                            failure: error.localizedDescription
                        )
                    }
                }
            }

            for await outcome in group {
                switch outcome {
                case .channel(let channel, nil):
                    if ownedChannels[channel.id] === channel {
                        ownedChannels.removeValue(forKey: channel.id)
                    }
                case .channel(let channel, .some(let failure)):
                    ownedChannels[channel.id] = channel
                    failures.append(
                        "Channel '\(channel.id)' cleanup failed: \(failure)"
                    )
                case .session(nil):
                    sessionShutdownPending = false
                case .session(.some(let failure)):
                    failures.append(failure)
                }
            }
        }
        peers.removeAll()
        announcedDescriptors.removeAll()
        let hasPendingResources = !ownedChannels.isEmpty
            || sessionShutdownPending
        if hasPendingResources, failures.isEmpty {
            failures.append(
                "PeerConnectivity cleanup ended while resources were still owned"
            )
        }
        return CleanupResult(
            failures: failures.sorted(),
            hasPendingResources: hasPendingResources
        )
    }

    private func validateConfiguration() throws {
        guard !invocationProtocolID.trimmingCharacters(
            in: .whitespacesAndNewlines
        ).isEmpty,
        !announcementProtocolID.trimmingCharacters(
            in: .whitespacesAndNewlines
        ).isEmpty else {
            throw PeerConnectivitySymbioError.invalidConfiguration(
                "protocol identifiers must not be empty"
            )
        }
        guard invocationProtocolID != announcementProtocolID else {
            throw PeerConnectivitySymbioError.invalidConfiguration(
                "invocation and announcement protocol identifiers must differ"
            )
        }
        guard eventCapacity > 0 else {
            throw PeerConnectivitySymbioError.invalidConfiguration(
                "event capacity must be greater than zero"
            )
        }
        guard maximumPendingReplies > 0 else {
            throw PeerConnectivitySymbioError.invalidConfiguration(
                "pending reply capacity must be greater than zero"
            )
        }
        guard maximumPendingChannels > 0 else {
            throw PeerConnectivitySymbioError.invalidConfiguration(
                "pending channel capacity must be greater than zero"
            )
        }
        guard maximumConcurrentOperations > 0 else {
            throw PeerConnectivitySymbioError.invalidConfiguration(
                "concurrent operation capacity must be greater than zero"
            )
        }
        try wireCodec.validateConfiguration()
        guard channelOperationTimeout > .zero else {
            throw PeerConnectivitySymbioError.invalidConfiguration(
                "channel operation timeout must be greater than zero"
            )
        }
    }

    private func performChannelOperation<Value: Sendable>(
        on channel: PeerConnectivityOwnedChannel,
        operation: @escaping @Sendable () async throws -> Value
    ) async throws -> Value {
        do {
            return try await withPeerConnectivityDeadline(
                channelOperationTimeout,
                timer: timer,
                onCancellation: { _ in
                    try await self.closeOwned(channel)
                },
                operation: operation
            )
        } catch is CancellationError {
            throw cancellationError(
                unexpectedMessage: "Channel operation cancelled without owner cancellation"
            )
        } catch let error as PeerConnectivitySymbioError {
            throw error
        } catch {
            throw PeerConnectivitySymbioError.backendFailed(
                error.localizedDescription
            )
        }
    }

    private func cancellationError(
        unexpectedMessage: String
    ) -> any Error {
        if Task.isCancelled {
            return CancellationError()
        }
        switch stopCause {
        case .requested:
            return CancellationError()
        case .failure(let error):
            return error
        case nil:
            return PeerConnectivitySymbioError.backendFailed(
                unexpectedMessage
            )
        }
    }

    private func finishUnexpectedShutdown(
        with terminalError: PeerConnectivitySymbioError
    ) async {
        guard case .stopping = state else {
            return
        }
        let cleanup = await completeResourceCleanup()
        let finalError: PeerConnectivitySymbioError
        if cleanup.failures.isEmpty {
            finalError = terminalError
        } else {
            finalError = .cleanupFailed(
                [terminalError.localizedDescription] + cleanup.failures
            )
        }
        cleanupTask = nil
        finish(
            with: finalError,
            cleanupPending: cleanup.hasPendingResources
        )
    }

    private func throwCleanupFailureIfPresent() throws {
        if case .cleanupFailed(let error) = state {
            throw error
        }
    }

    private func finish(
        with error: PeerConnectivitySymbioError?,
        cleanupPending: Bool
    ) {
        if cleanupPending, let error {
            state = .cleanupFailed(error)
        } else {
            state = .finished(error)
        }
        queuedEvents.removeAll()
        let receiver = self.receiver
        self.receiver = nil
        if let error {
            receiver?.resume(throwing: error)
        } else {
            receiver?.resume(returning: nil)
        }
    }

    private func beginIO() throws {
        guard case .running = state else {
            throw PeerConnectivitySymbioError.invalidLifecycle(
                "The link is not accepting I/O"
            )
        }
        guard activeIOCount < maximumConcurrentOperations else {
            throw PeerConnectivitySymbioError.operationCapacityExceeded(
                maximumConcurrentOperations
            )
        }
        activeIOCount += 1
    }

    /// Tracks completion work that was already admitted through a bounded
    /// pending-reply slot. It must be allowed to drain even when the capacity
    /// for new outbound work is exhausted.
    private func beginAdmittedReplyIO() throws {
        guard case .running = state else {
            throw PeerConnectivitySymbioError.invalidLifecycle(
                "The link is not accepting I/O"
            )
        }
        activeIOCount += 1
        activeReplyCount += 1
    }

    private func endAdmittedReplyIO() {
        activeReplyCount -= 1
        endIO()
    }

    private func cancelChannelAcquisition(
        _ channelSlot: PeerConnectivityOwnedChannelSlot,
        operation: String
    ) async throws {
        if let channel = channelSlot.current() {
            do {
                try await closeOwned(channel)
            } catch {
                throw PeerConnectivitySymbioError.cleanupFailed([
                    "Failed to close the cancelled \(operation) channel",
                    error.localizedDescription,
                ])
            }
            return
        }

        await terminateUnexpectedly(.backendFailed(
            "Cancelled \(operation) did not yet own a channel; session shutdown is required to drain channel acquisition"
        ))
        try await sessionOwner.shutdown()
    }

    private func endIO() {
        activeIOCount -= 1
        guard activeIOCount == 0 else {
            return
        }
        let waiters = ioDrainWaiters
        ioDrainWaiters.removeAll()
        for waiter in waiters {
            waiter.resume()
        }
    }

    private func waitForIODrain() async {
        guard activeIOCount > 0 else {
            return
        }
        await withCheckedContinuation { continuation in
            ioDrainWaiters.append(continuation)
        }
    }

    private static func authentication(
        for peer: PeerConnectivityPeer
    ) -> SymbioPeerAuthentication {
        var attributes = peer.metadata
        attributes["peerConnectivity.transportPeerID"] = peer.id
        switch peer.identity {
        case .backend(let kind, let value):
            attributes["peerConnectivity.backendKind"] = kind
            return SymbioPeerAuthentication(
                method: "peer-connectivity:\(kind)",
                subject: value,
                attributes: attributes
            )
        case nil:
            return SymbioPeerAuthentication(
                method: "peer-connectivity:unverified",
                subject: peer.id,
                attributes: attributes
            )
        }
    }

    private static func validatedTransportPeerID(
        for peer: PeerConnectivityPeer
    ) throws -> TransportPeerID {
        guard !peer.id.trimmingCharacters(
            in: .whitespacesAndNewlines
        ).isEmpty else {
            throw PeerConnectivitySymbioError.backendFailed(
                "PeerConnectivity produced an empty transport peer identifier"
            )
        }
        return TransportPeerID(rawValue: peer.id)
    }

    private static func validateOpenedChannel(
        _ channel: any PeerConnectivityChannel,
        expectedPeer: PeerConnectivityPeer,
        expectedProtocolID: String
    ) throws {
        guard hasSameTransportIdentity(channel.peer, expectedPeer) else {
            throw PeerConnectivitySymbioError.backendFailed(
                "Opened channel was bound to a different peer identity"
            )
        }
        guard channel.protocolID == expectedProtocolID else {
            throw PeerConnectivitySymbioError.backendFailed(
                "Opened channel did not preserve the requested protocol identifier"
            )
        }
    }

    private func validateCurrentPeer(
        _ peer: PeerConnectivityPeer,
        generation: UInt64
    ) throws {
        let peerID = try Self.validatedTransportPeerID(for: peer)
        guard let currentPeer = peers[peerID],
              Self.hasSameTransportIdentity(currentPeer, peer),
              peerGenerations[peerID] == generation else {
            throw PeerConnectivitySymbioError.peerUnavailable(peerID)
        }
    }

    private static func hasSameTransportIdentity(
        _ lhs: PeerConnectivityPeer,
        _ rhs: PeerConnectivityPeer
    ) -> Bool {
        lhs.id == rhs.id && lhs.identity == rhs.identity
    }

    private func validateCurrentPeer(
        _ peerID: TransportPeerID,
        generation: UInt64
    ) throws {
        guard peers[peerID] != nil,
              peerGenerations[peerID] == generation else {
            throw PeerConnectivitySymbioError.peerUnavailable(peerID)
        }
    }

    private func closeOwned(
        _ channel: PeerConnectivityOwnedChannel
    ) async throws {
        ownedChannels[channel.id] = channel
        do {
            try await channel.close()
            if ownedChannels[channel.id] === channel {
                ownedChannels.removeValue(forKey: channel.id)
            }
        } catch {
            ownedChannels[channel.id] = channel
            throw PeerConnectivitySymbioError.cleanupFailed([
                "Channel '\(channel.id)' cleanup failed: \(error.localizedDescription)"
            ])
        }
    }

    private func retainOwnedChannel(
        _ channel: PeerConnectivityOwnedChannel
    ) throws {
        ownedChannels[channel.id] = channel
        switch state {
        case .starting, .running:
            return
        case .idle, .stopping, .cleanupFailed, .finished:
            throw PeerConnectivitySymbioError.invalidLifecycle(
                "The link stopped before the channel became usable"
            )
        }
    }
}
