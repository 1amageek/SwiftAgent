import Foundation
import NetworkingCore
import Testing
@testable import SwiftAgentSymbio

@Suite("Symbio runtime boundaries")
struct SymbioRuntimeTests {
    @Test("Invalid runtime capacities fail instead of being clamped", .timeLimit(.minutes(1)))
    func invalidRuntimeCapacityFailsClosed() {
        let link = TestSymbioLink()
        #expect(throws: SymbioRuntimeError.self) {
            _ = try SymbioRuntime(
                identity: ParticipantDescriptor(
                    id: "runtime.local",
                    kind: .service
                ),
                link: link,
                maximumPendingInboundInvocations: 0
            )
        }
    }

    @Test("Invalid runtime identity fails during construction")
    func invalidRuntimeIdentityFailsConstruction() {
        let identity = ParticipantDescriptor(
            id: "runtime.local",
            kind: .service,
            selfClaims: [Claim(
                subjectID: "runtime.local",
                predicate: "trust",
                object: "local",
                issuerID: "runtime.local",
                confidence: 1.1
            )]
        )

        #expect(throws: SymbioRuntimeError.self) {
            _ = try SymbioRuntime(identity: identity)
        }
    }

    @Test("Invalid endpoint descriptors never enter runtime state")
    func invalidEndpointDescriptorIsRejected() async throws {
        let runtime = try makeRuntime(link: TestSymbioLink())
        let representation = MessageRepresentation.typedPayload(schema: " ")
        let endpoint = DescriptorParticipantEndpoint(descriptor: ParticipantDescriptor(
            id: "invalid.local",
            kind: .agent,
            representations: [representation],
            capabilityContracts: [CapabilityContract(
                id: "invalid.invoke",
                input: representation
            )]
        ))

        await #expect(throws: SymbioRuntimeError.self) {
            try await runtime.register(endpoint)
        }
        #expect(await runtime.participantView(for: "invalid.local") == nil)
    }

    @Test("Invalid change stream capacity is observable", .timeLimit(.minutes(1)))
    func invalidChangeStreamCapacityFailsClosed() async throws {
        let runtime = try makeRuntime(link: TestSymbioLink())
        let stream = await runtime.changes(bufferingOldest: 0)
        var iterator = stream.makeAsyncIterator()

        do {
            _ = try await iterator.next()
            Issue.record("Expected invalid change stream capacity to fail")
        } catch is SymbioRuntimeError {
            // Expected typed configuration failure.
        } catch {
            Issue.record("Unexpected change stream failure: \(error)")
        }
    }

    @Test("Runtime publishes one complete local participant catalog", .timeLimit(.minutes(1)))
    func startupPublishesCompleteCatalog() async throws {
        let link = TestSymbioLink()
        let runtime = try makeRuntime(link: link)
        _ = try await runtime.register(TestParticipantEndpoint(id: "worker.local"))

        try await runtime.start()

        #expect(await link.synchronizedParticipantIDs() == [[
            "runtime.local",
            "worker.local",
        ]])
        try await runtime.stop()
    }

    @Test("Local endpoint invocation uses an owned participant handle", .timeLimit(.minutes(1)))
    func localInvocationUsesOwnedHandle() async throws {
        let link = TestSymbioLink()
        let runtime = try makeRuntime(link: link)
        let endpoint = TestParticipantEndpoint(id: "worker.local")
        let handle = try await runtime.register(endpoint)
        try await runtime.start()

        let input = OwnedBytes(consuming: Array("work".utf8))
        let result = try await runtime.invoke(
            TestParticipantEndpoint.capability,
            on: handle.participantID,
            representation: TestParticipantEndpoint.representation,
            with: input,
            from: runtime.localHandle
        )

        #expect(result == input)
        #expect(await endpoint.invocationCount() == 1)
        try await runtime.stop()
    }

    @Test("Stopping a runtime invalidates a late local result", .timeLimit(.minutes(1)))
    func stopInvalidatesLateLocalResult() async throws {
        let link = TestSymbioLink()
        let runtime = try makeRuntime(link: link)
        let endpoint = BlockingParticipantEndpoint(id: "worker.local")
        let handle = try await runtime.register(endpoint)
        try await runtime.start()

        let invocation = Task {
            try await runtime.invoke(
                TestParticipantEndpoint.capability,
                on: handle.participantID,
                representation: TestParticipantEndpoint.representation,
                with: OwnedBytes(consuming: Array("work".utf8)),
                from: runtime.localHandle
            )
        }
        await endpoint.waitUntilInvocationStarts()
        let stop = Task {
            try await runtime.stop()
        }
        await endpoint.waitUntilShutdownStarts()

        await #expect(throws: SymbioRuntimeError.self) {
            try await invocation.value
        }
        try await stop.value
    }

    @Test("Stopping interrupts and drains a catalog publication", .timeLimit(.minutes(1)))
    func stopDrainsCatalogPublication() async throws {
        let link = TestSymbioLink()
        let runtime = try makeRuntime(link: link)
        try await runtime.start()
        let endpoint = TestParticipantEndpoint(id: "publishing.local")
        await link.blockNextSynchronization()

        let registration = Task {
            try await runtime.register(endpoint)
        }
        await link.waitUntilSynchronizationStarts()

        try await runtime.stop()
        await #expect(throws: SymbioRuntimeError.self) {
            try await registration.value
        }
        #expect(await endpoint.shutdownCount() == 1)
    }

    @Test("Sender authority is revalidated after policy suspension", .timeLimit(.minutes(1)))
    func senderAuthorityIsRevalidatedAfterPolicySuspension() async throws {
        let link = TestSymbioLink()
        let runtime = try makeRuntime(link: link)
        let sender = try await runtime.register(
            TestParticipantEndpoint(id: "sender.local")
        )
        let targetEndpoint = TestParticipantEndpoint(
            id: "worker.local",
            requiredPolicies: ["policy.invoke"]
        )
        let target = try await runtime.register(targetEndpoint)
        let authorizer = BlockingPolicyAuthorizer()
        try await runtime.start()

        let invocation = Task {
            try await runtime.invoke(
                TestParticipantEndpoint.capability,
                on: target.participantID,
                representation: TestParticipantEndpoint.representation,
                with: OwnedBytes(consuming: Array("work".utf8)),
                from: sender,
                authorizer: authorizer
            )
        }
        await authorizer.waitUntilStarted()
        try await runtime.setAvailability(
            .unavailable(reason: "sender authority revoked"),
            for: sender
        )
        await authorizer.release()

        await #expect(throws: SymbioRuntimeError.self) {
            try await invocation.value
        }
        #expect(await targetEndpoint.invocationCount() == 0)
        try await runtime.stop()
    }

    @Test("Unverified participant claims fail closed", .timeLimit(.minutes(1)))
    func unverifiedClaimFailsClosed() async throws {
        let link = TestSymbioLink()
        let runtime = try SymbioRuntime(
            identity: ParticipantDescriptor(id: "runtime.local", kind: .service),
            link: link
        )
        let changeStream = await runtime.changes()
        var changes = changeStream.makeAsyncIterator()
        try await runtime.start()

        await link.emit(.peerConnected("transport.remote"))
        await link.emit(.peerClaimed(makeClaim()))

        guard case .participantClaimRejected(let peerID, _) = try await changes.next() else {
            Issue.record("Expected a rejected participant claim")
            try await runtime.stop()
            return
        }
        #expect(peerID == "transport.remote")
        #expect(await runtime.participantView(for: "worker.remote") == nil)
        try await runtime.stop()
    }

    @Test("Malformed authentication is rejected before verification", .timeLimit(.minutes(1)))
    func malformedAuthenticationSkipsVerifier() async throws {
        let link = TestSymbioLink()
        let verifier = AcceptingClaimVerifier()
        let runtime = try SymbioRuntime(
            identity: ParticipantDescriptor(id: "runtime.local", kind: .service),
            link: link,
            claimVerifier: verifier
        )
        let changeStream = await runtime.changes()
        var changes = changeStream.makeAsyncIterator()
        try await runtime.start()
        let claim = makeClaim()

        await link.emit(.peerConnected(claim.transportPeerID))
        await link.emit(.peerClaimed(SymbioPeerClaim(
            transportPeerID: claim.transportPeerID,
            descriptor: claim.descriptor,
            authentication: SymbioPeerAuthentication(
                method: " ",
                subject: claim.authentication.subject
            )
        )))

        guard case .participantClaimRejected = try await changes.next() else {
            Issue.record("Malformed authentication was not rejected")
            try await runtime.stop()
            return
        }
        #expect(await verifier.verificationCount() == 0)
        #expect(await runtime.participantView(for: "worker.remote") == nil)
        try await runtime.stop()
    }

    @Test("Verifier output requires a nonempty verification method", .timeLimit(.minutes(1)))
    func emptyVerificationMethodIsRejected() async throws {
        let link = TestSymbioLink()
        let runtime = try SymbioRuntime(
            identity: ParticipantDescriptor(id: "runtime.local", kind: .service),
            link: link,
            claimVerifier: EmptyMethodClaimVerifier()
        )
        let changeStream = await runtime.changes()
        var changes = changeStream.makeAsyncIterator()
        try await runtime.start()

        await link.emit(.peerConnected("transport.remote"))
        await link.emit(.peerClaimed(makeClaim()))

        guard case .participantClaimRejected = try await changes.next() else {
            Issue.record("An invalid verifier binding entered runtime state")
            try await runtime.stop()
            return
        }
        #expect(await runtime.participantView(for: "worker.remote") == nil)
        try await runtime.stop()
    }

    @Test("Unexpected verifier cancellation is rejected", .timeLimit(.minutes(1)))
    func unexpectedVerifierCancellationIsRejected() async throws {
        let link = TestSymbioLink()
        let runtime = try SymbioRuntime(
            identity: ParticipantDescriptor(id: "runtime.local", kind: .service),
            link: link,
            claimVerifier: UnexpectedlyCancellingClaimVerifier()
        )
        let changeStream = await runtime.changes()
        var changes = changeStream.makeAsyncIterator()
        try await runtime.start()

        await link.emit(.peerConnected("transport.remote"))
        await link.emit(.peerClaimed(makeClaim()))

        guard case .participantClaimRejected = try await changes.next() else {
            Issue.record("Unexpected verifier cancellation was silently discarded")
            try await runtime.stop()
            return
        }
        #expect(await runtime.participantView(for: "worker.remote") == nil)
        try await runtime.stop()
    }

    @Test("Verified participant identity is routed through its transport binding", .timeLimit(.minutes(1)))
    func verifiedIdentityUsesTransportBinding() async throws {
        let link = TestSymbioLink()
        let runtime = try makeRuntime(link: link)
        let changeStream = await runtime.changes()
        var changes = changeStream.makeAsyncIterator()
        try await runtime.start()

        await link.emit(.peerConnected("transport.remote"))
        await link.emit(.peerClaimed(makeClaim()))
        guard case .joined(let participant) = try await changes.next() else {
            Issue.record("Expected the verified participant to join")
            try await runtime.stop()
            return
        }

        let input = OwnedBytes(consuming: Array("remote".utf8))
        let result = try await runtime.invoke(
            TestParticipantEndpoint.capability,
            on: participant.id,
            representation: TestParticipantEndpoint.representation,
            with: input,
            from: runtime.localHandle
        )

        #expect(result == input)
        #expect(await link.lastInvokedPeerID() == "transport.remote")
        try await runtime.stop()
    }

    @Test("Inbound invocation is denied unless an authorizer allows it", .timeLimit(.minutes(1)))
    func inboundInvocationDefaultsToDeny() async throws {
        let link = TestSymbioLink()
        let runtime = try makeRuntime(link: link)
        let endpoint = TestParticipantEndpoint(id: "worker.local")
        _ = try await runtime.register(endpoint)
        let changeStream = await runtime.changes()
        var changes = changeStream.makeAsyncIterator()
        try await runtime.start()
        await link.emit(.peerConnected("transport.remote"))
        await link.emit(.peerClaimed(makeClaim()))
        _ = try await changes.next()

        let envelope = makeInboundEnvelope(recipientID: "worker.local")
        await link.emit(.invocationReceived(
            envelope: envelope,
            replyContext: SymbioReplyContext(
                id: "reply-1",
                transportPeerID: "transport.remote"
            )
        ))
        let reply = await link.nextReply()

        guard case .failure(let failure) = reply.outcome else {
            Issue.record("Expected inbound invocation denial")
            try await runtime.stop()
            return
        }
        #expect(failure.code == .unauthorized)
        #expect(await endpoint.invocationCount() == 0)
        try await runtime.stop()
    }

    @Test("Authorized inbound invocation reaches only its registered endpoint", .timeLimit(.minutes(1)))
    func authorizedInboundInvocationReachesEndpoint() async throws {
        let link = TestSymbioLink()
        let runtime = try makeRuntime(
            link: link,
            inboundAuthorizer: AllowingInboundInvocationAuthorizer()
        )
        let endpoint = TestParticipantEndpoint(id: "worker.local")
        _ = try await runtime.register(endpoint)
        let changeStream = await runtime.changes()
        var changes = changeStream.makeAsyncIterator()
        try await runtime.start()
        await link.emit(.peerConnected("transport.remote"))
        await link.emit(.peerClaimed(makeClaim()))
        _ = try await changes.next()

        let envelope = makeInboundEnvelope(recipientID: "worker.local")
        await link.emit(.invocationReceived(
            envelope: envelope,
            replyContext: SymbioReplyContext(
                id: "reply-2",
                transportPeerID: "transport.remote"
            )
        ))
        let reply = await link.nextReply()

        guard case .success(let result) = reply.outcome else {
            Issue.record("Expected an authorized invocation result")
            try await runtime.stop()
            return
        }
        #expect(result == envelope.arguments)
        #expect(await endpoint.invocationCount() == 1)
        try await runtime.stop()
    }

    @Test("Unexpected endpoint cancellation is an internal failure", .timeLimit(.minutes(1)))
    func unexpectedEndpointCancellationIsInternalFailure() async throws {
        let link = TestSymbioLink()
        let runtime = try makeRuntime(
            link: link,
            inboundAuthorizer: AllowingInboundInvocationAuthorizer()
        )
        let endpoint = UnexpectedlyCancellingParticipantEndpoint(
            id: "worker.local"
        )
        _ = try await runtime.register(endpoint)
        let changeStream = await runtime.changes()
        var changes = changeStream.makeAsyncIterator()
        try await runtime.start()
        await link.emit(.peerConnected("transport.remote"))
        await link.emit(.peerClaimed(makeClaim()))
        _ = try await changes.next()

        await link.emit(.invocationReceived(
            envelope: makeInboundEnvelope(recipientID: "worker.local"),
            replyContext: SymbioReplyContext(
                id: "reply-unexpected-cancellation",
                transportPeerID: "transport.remote"
            )
        ))
        let reply = await link.nextReply()

        guard case .failure(let failure) = reply.outcome else {
            Issue.record("Unexpected endpoint cancellation was treated as success")
            try await runtime.stop()
            return
        }
        #expect(failure.code == .internalError)
        try await runtime.stop()
    }

    @Test("Inbound execution budget includes authorization", .timeLimit(.minutes(1)))
    func inboundExecutionBudgetIncludesAuthorization() async throws {
        let link = TestSymbioLink()
        let runtime = try makeRuntime(
            link: link,
            inboundAuthorizer: DelayedInboundInvocationAuthorizer(
                delay: .seconds(5)
            ),
            maximumInboundExecutionDuration: .milliseconds(20)
        )
        let endpoint = TestParticipantEndpoint(id: "worker.local")
        _ = try await runtime.register(endpoint)
        let changeStream = await runtime.changes()
        var changes = changeStream.makeAsyncIterator()
        try await runtime.start()
        await link.emit(.peerConnected("transport.remote"))
        await link.emit(.peerClaimed(makeClaim()))
        _ = try await changes.next()

        await link.emit(.invocationReceived(
            envelope: makeInboundEnvelope(recipientID: "worker.local"),
            replyContext: SymbioReplyContext(
                id: "reply-authorization-deadline",
                transportPeerID: "transport.remote"
            )
        ))
        let reply = await link.nextReply()

        guard case .failure(let failure) = reply.outcome else {
            Issue.record("Expected the authorization deadline to fail")
            try await runtime.stop()
            return
        }
        #expect(failure.code == .deadlineExceeded)
        #expect(await endpoint.invocationCount() == 0)
        try await runtime.stop()
    }

    @Test("Failed catalog withdrawal restores the local endpoint", .timeLimit(.minutes(1)))
    func failedWithdrawalRestoresEndpoint() async throws {
        let link = TestSymbioLink()
        let runtime = try makeRuntime(link: link)
        let endpoint = TestParticipantEndpoint(id: "worker.local")
        let handle = try await runtime.register(endpoint)
        try await runtime.start()
        await link.failNextSynchronization()

        await #expect(throws: SymbioRuntimeError.self) {
            try await runtime.remove(handle)
        }

        let input = OwnedBytes(consuming: Array("still-owned".utf8))
        let result = try await runtime.invoke(
            TestParticipantEndpoint.capability,
            on: handle.participantID,
            representation: TestParticipantEndpoint.representation,
            with: input,
            from: runtime.localHandle
        )
        #expect(result == input)
        #expect(await endpoint.invocationCount() == 1)
        try await runtime.stop()
    }

    @Test("Blocked remote senders remain denied after policy approval", .timeLimit(.minutes(1)))
    func blockedRemoteSenderCannotInvoke() async throws {
        let link = TestSymbioLink()
        let runtime = try makeRuntime(
            link: link,
            inboundAuthorizer: AllowingInboundInvocationAuthorizer()
        )
        let endpoint = TestParticipantEndpoint(id: "worker.local")
        _ = try await runtime.register(endpoint)
        let changeStream = await runtime.changes()
        var changes = changeStream.makeAsyncIterator()
        try await runtime.start()
        await link.emit(.peerConnected("transport.remote"))
        await link.emit(.peerClaimed(makeClaim()))
        _ = try await changes.next()
        await runtime.block("worker.remote", reason: "operator decision")

        let envelope = makeInboundEnvelope(recipientID: "worker.local")
        await link.emit(.invocationReceived(
            envelope: envelope,
            replyContext: SymbioReplyContext(
                id: "reply-blocked",
                transportPeerID: "transport.remote"
            )
        ))
        let reply = await link.nextReply()

        guard case .failure(let failure) = reply.outcome else {
            Issue.record("Expected blocked remote sender to be denied")
            try await runtime.stop()
            return
        }
        #expect(failure.code == .unauthorized)
        #expect(await endpoint.invocationCount() == 0)
        try await runtime.stop()
    }

    @Test("Cleanup failure keeps link ownership for retry", .timeLimit(.minutes(1)))
    func cleanupFailureCanBeRetried() async throws {
        let link = TestSymbioLink(shutdownFailures: 1)
        let runtime = try makeRuntime(link: link)
        try await runtime.start()

        await #expect(throws: SymbioRuntimeError.self) {
            try await runtime.stop()
        }
        try await runtime.stop()

        #expect(await link.shutdownAttemptCount() == 2)
    }

    @Test("Runtime cleanup outlives a cancelled stop caller", .timeLimit(.minutes(1)))
    func runtimeOwnsCleanupAfterCallerCancellation() async throws {
        let link = TestSymbioLink(blockShutdownUntilReleased: true)
        let runtime = try makeRuntime(link: link)
        try await runtime.start()

        let stop = Task {
            try await runtime.stop()
        }
        await link.waitUntilShutdownStarts()
        stop.cancel()
        await link.releaseShutdown()

        try await stop.value
        #expect(await link.shutdownAttemptCount() == 1)
        #expect(await link.shutdownObservedCallerCancellation() == false)
    }

    @Test("Unexpected link cancellation fails the running runtime", .timeLimit(.minutes(1)))
    func unexpectedLinkCancellationFailsRuntime() async throws {
        let link = TestSymbioLink()
        let runtime = try makeRuntime(link: link)
        let changeStream = await runtime.changes()
        var changes = changeStream.makeAsyncIterator()
        try await runtime.start()

        await link.cancelReceiveUnexpectedly()

        guard case .becameUnavailable("runtime.local") = try await changes.next() else {
            Issue.record("Expected the runtime identity to become unavailable")
            try await runtime.stop()
            return
        }
        guard case .linkFailed = try await changes.next() else {
            Issue.record("Expected unexpected link cancellation to fail the runtime")
            try await runtime.stop()
            return
        }
        #expect(
            await runtime.participantView(for: "runtime.local")?
                .availability.state == .unavailable
        )
        try await runtime.stop()
    }

    @Test("Runtime shutdown unblocks an inbound reply", .timeLimit(.minutes(1)))
    func shutdownUnblocksInboundReply() async throws {
        let link = TestSymbioLink(blockRepliesUntilShutdown: true)
        let runtime = try makeRuntime(
            link: link,
            inboundAuthorizer: AllowingInboundInvocationAuthorizer()
        )
        _ = try await runtime.register(
            TestParticipantEndpoint(id: "worker.local")
        )
        let changeStream = await runtime.changes()
        var changes = changeStream.makeAsyncIterator()
        try await runtime.start()
        await link.emit(.peerConnected("transport.remote"))
        await link.emit(.peerClaimed(makeClaim()))
        _ = try await changes.next()

        await link.emit(.invocationReceived(
            envelope: makeInboundEnvelope(recipientID: "worker.local"),
            replyContext: SymbioReplyContext(
                id: "reply-blocked-until-shutdown",
                transportPeerID: "transport.remote"
            )
        ))
        await link.waitUntilSendStarts()

        try await runtime.stop()
    }

    @Test("Disconnected bindings cannot complete an invocation", .timeLimit(.minutes(1)))
    func disconnectedBindingCannotCompleteInvocation() async throws {
        let link = TestSymbioLink(blockInvocationsUntilReleased: true)
        let runtime = try makeRuntime(link: link)
        let changeStream = await runtime.changes()
        var changes = changeStream.makeAsyncIterator()
        try await runtime.start()
        await link.emit(.peerConnected("transport.remote"))
        await link.emit(.peerClaimed(makeClaim()))
        _ = try await changes.next()

        let invocation = Task {
            try await runtime.invoke(
                TestParticipantEndpoint.capability,
                on: "worker.remote",
                representation: TestParticipantEndpoint.representation,
                with: OwnedBytes(consuming: Array("remote".utf8)),
                from: runtime.localHandle
            )
        }
        await link.waitUntilInvocationStarts()
        await link.emit(.peerDisconnected("transport.remote"))
        guard case .becameUnavailable(let participantID) = try await changes.next() else {
            Issue.record("Expected the disconnected participant to become unavailable")
            await link.releaseInvocation()
            do {
                _ = try await invocation.value
                Issue.record("Expected the disconnected invocation to fail")
            } catch is SymbioRuntimeError {
                // The expected runtime failure has drained the test task.
            } catch {
                Issue.record("Unexpected invocation failure: \(error)")
            }
            try await runtime.stop()
            return
        }
        #expect(participantID == "worker.remote")
        await link.releaseInvocation()

        await #expect(throws: SymbioRuntimeError.self) {
            try await invocation.value
        }
        let remoteView = await runtime.participantView(for: "worker.remote")
        #expect(remoteView?.evidence.isEmpty == true)
        try await runtime.stop()
    }

    @Test("Peer disconnection cancels its active inbound invocation", .timeLimit(.minutes(1)))
    func peerDisconnectionCancelsInboundInvocation() async throws {
        let link = TestSymbioLink()
        let runtime = try makeRuntime(
            link: link,
            inboundAuthorizer: AllowingInboundInvocationAuthorizer()
        )
        let endpoint = CancellationObservingParticipantEndpoint(id: "worker.local")
        _ = try await runtime.register(endpoint)
        var changes = await runtime.changes().makeAsyncIterator()
        try await runtime.start()
        await link.emit(.peerConnected("transport.remote"))
        await link.emit(.peerClaimed(makeClaim()))
        guard case .joined = try await changes.next() else {
            Issue.record("Expected the verified participant to join")
            try await runtime.stop()
            return
        }

        await link.emit(.invocationReceived(
            envelope: makeInboundEnvelope(recipientID: "worker.local"),
            replyContext: SymbioReplyContext(
                id: "reply-disconnected-inbound",
                transportPeerID: "transport.remote"
            )
        ))
        await endpoint.waitUntilInvocationStarts()
        await link.emit(.peerDisconnected("transport.remote"))
        await endpoint.waitUntilCancellationIsObserved()

        let reply = await link.nextReply()
        guard case .failure(let failure) = reply.outcome else {
            Issue.record("Expected the disconnected inbound invocation to fail")
            try await runtime.stop()
            return
        }
        #expect(failure.code == .unavailable)
        let availableIDs = await runtime.availableParticipants.map(\.id)
        #expect(!availableIDs.contains("worker.remote"))
        try await runtime.stop()
    }

    @Test("A blocked recipient cannot complete an in-flight invocation", .timeLimit(.minutes(1)))
    func blockedRecipientCannotCompleteInvocation() async throws {
        let link = TestSymbioLink(blockInvocationsUntilReleased: true)
        let runtime = try makeRuntime(link: link)
        try await runtime.start()
        var changes = await runtime.changes().makeAsyncIterator()

        await link.emit(.peerConnected("transport.remote"))
        await link.emit(.peerClaimed(makeClaim()))
        guard case .joined = try await changes.next() else {
            Issue.record("Expected the verified participant to join")
            try await runtime.stop()
            return
        }

        let invocation = Task {
            try await runtime.invoke(
                TestParticipantEndpoint.capability,
                on: "worker.remote",
                representation: TestParticipantEndpoint.representation,
                with: OwnedBytes(consuming: Array("request".utf8)),
                from: runtime.localHandle
            )
        }
        await link.waitUntilInvocationStarts()
        await runtime.block("worker.remote", reason: "operator revoked routing")
        await link.releaseInvocation()

        await #expect(throws: SymbioRuntimeError.self) {
            try await invocation.value
        }
        try await runtime.stop()
    }

    @Test("Stopped participants are explicitly unavailable", .timeLimit(.minutes(1)))
    func stoppedParticipantsBecomeUnavailable() async throws {
        let link = TestSymbioLink()
        let runtime = try makeRuntime(link: link)
        let handle = try await runtime.register(
            TestParticipantEndpoint(id: "worker.local")
        )
        try await runtime.start()

        try await runtime.stop()

        let runtimeView = await runtime.participantView(for: runtime.identity.id)
        let endpointView = await runtime.participantView(for: handle.participantID)
        #expect(runtimeView?.availability.state == .unavailable)
        #expect(endpointView?.availability.state == .unavailable)
        #expect(await runtime.availableParticipants.isEmpty)
    }

    @Test("Policy approval must cover every required policy", .timeLimit(.minutes(1)))
    func partialPolicyApprovalIsDenied() async throws {
        let link = TestSymbioLink()
        let runtime = try makeRuntime(link: link)
        let endpoint = TestParticipantEndpoint(
            id: "worker.local",
            requiredPolicies: ["policy.audit", "policy.user-consent"]
        )
        let handle = try await runtime.register(endpoint)
        let message = Message(
            senderID: runtime.identity.id,
            addressing: .direct(handle.participantID),
            representation: TestParticipantEndpoint.representation,
            payload: OwnedBytes(),
            intent: TestParticipantEndpoint.capability
        )
        let plan = await runtime.planRoute(for: message)
        let authorized = await runtime.authorize(
            plan,
            using: PartialPolicyAuthorizer()
        )

        #expect(authorized.policyDecision.state == .denied)
    }

    @Test("Expired members do not satisfy aggregate availability")
    func expiredMembersAreExcludedFromAggregateRollup() async throws {
        let runtime = try makeRuntime(link: TestSymbioLink())
        let member = try await runtime.register(
            TestParticipantEndpoint(id: "member.local")
        )
        try await runtime.setAvailability(
            Availability(
                state: .available,
                expiresAt: Date.distantPast
            ),
            for: member
        )
        try await runtime.register(AggregateParticipantDescriptor(
            id: "aggregate.local",
            kind: .team,
            members: [AggregateMember(id: member.participantID)],
            rollupPolicy: RollupPolicy(availabilityRule: .all)
        ))

        let aggregate = await runtime.participantView(for: "aggregate.local")
        #expect(aggregate?.availability.state == .unavailable)
    }

    @Test("Nested aggregate availability converges in one state transition")
    func nestedAggregateAvailabilityConverges() async throws {
        let runtime = try makeRuntime(link: TestSymbioLink())
        let member = try await runtime.register(
            TestParticipantEndpoint(id: "nested.member")
        )
        try await runtime.register(AggregateParticipantDescriptor(
            id: "nested.child",
            kind: .team,
            members: [AggregateMember(id: member.participantID)],
            rollupPolicy: RollupPolicy(availabilityRule: .all)
        ))
        try await runtime.register(AggregateParticipantDescriptor(
            id: "nested.parent",
            kind: .team,
            members: [AggregateMember(id: "nested.child")],
            rollupPolicy: RollupPolicy(availabilityRule: .all)
        ))

        try await runtime.setAvailability(
            .unavailable(reason: "offline"),
            for: member
        )

        let child = await runtime.participantView(for: "nested.child")
        let parent = await runtime.participantView(for: "nested.parent")
        #expect(child?.availability.state == .unavailable)
        #expect(parent?.availability.state == .unavailable)
    }

    @Test("Aggregate membership cycles are rejected")
    func aggregateCyclesAreRejected() async throws {
        let runtime = try makeRuntime(link: TestSymbioLink())
        try await runtime.register(AggregateParticipantDescriptor(
            id: "cycle.first",
            kind: .team,
            members: [AggregateMember(id: "cycle.second")],
            rollupPolicy: RollupPolicy(availabilityRule: .all)
        ))

        await #expect(throws: SymbioRuntimeError.self) {
            try await runtime.register(AggregateParticipantDescriptor(
                id: "cycle.second",
                kind: .team,
                members: [AggregateMember(id: "cycle.first")],
                rollupPolicy: RollupPolicy(availabilityRule: .all)
            ))
        }
    }
}

private actor TestParticipantEndpoint: ParticipantEndpoint {
    static let capability = "test.echo"
    static let representation = MessageRepresentation.typedPayload(
        schema: "test.echo"
    )

    nonisolated let descriptor: ParticipantDescriptor
    private var count = 0
    private var shutdowns = 0

    init(
        id: ParticipantID,
        requiredPolicies: Set<String> = []
    ) {
        let contract = CapabilityContract(
            id: Self.capability,
            input: Self.representation,
            output: Self.representation,
            requiredPolicies: requiredPolicies
        )
        self.descriptor = ParticipantDescriptor(
            id: id,
            kind: .agent,
            representations: [Self.representation],
            capabilityContracts: [contract]
        )
    }

    func invoke(_ invocation: SymbioInvocation) async throws -> OwnedBytes? {
        count += 1
        return invocation.envelope.arguments
    }

    func shutdown() async {
        shutdowns += 1
    }

    func invocationCount() -> Int {
        count
    }

    func shutdownCount() -> Int {
        shutdowns
    }
}

private actor DescriptorParticipantEndpoint: ParticipantEndpoint {
    nonisolated let descriptor: ParticipantDescriptor

    init(descriptor: ParticipantDescriptor) {
        self.descriptor = descriptor
    }

    func invoke(_ invocation: SymbioInvocation) async throws -> OwnedBytes? {
        nil
    }

    func shutdown() async {}
}

private actor AcceptingClaimVerifier: ParticipantClaimVerifier {
    private var count = 0

    func verify(
        _ claim: SymbioPeerClaim
    ) async throws -> VerifiedParticipantBinding {
        count += 1
        return VerifiedParticipantBinding(
            transportPeerID: claim.transportPeerID,
            descriptor: claim.descriptor,
            verificationMethod: "test"
        )
    }

    func verificationCount() -> Int {
        count
    }
}

private struct EmptyMethodClaimVerifier: ParticipantClaimVerifier {
    func verify(
        _ claim: SymbioPeerClaim
    ) async throws -> VerifiedParticipantBinding {
        VerifiedParticipantBinding(
            transportPeerID: claim.transportPeerID,
            descriptor: claim.descriptor,
            verificationMethod: " "
        )
    }
}

private struct UnexpectedlyCancellingClaimVerifier: ParticipantClaimVerifier {
    func verify(
        _ claim: SymbioPeerClaim
    ) async throws -> VerifiedParticipantBinding {
        throw CancellationError()
    }
}

private actor UnexpectedlyCancellingParticipantEndpoint: ParticipantEndpoint {
    nonisolated let descriptor: ParticipantDescriptor

    init(id: ParticipantID) {
        let contract = CapabilityContract(
            id: TestParticipantEndpoint.capability,
            input: TestParticipantEndpoint.representation,
            output: TestParticipantEndpoint.representation
        )
        self.descriptor = ParticipantDescriptor(
            id: id,
            kind: .agent,
            representations: [TestParticipantEndpoint.representation],
            capabilityContracts: [contract]
        )
    }

    func invoke(_ invocation: SymbioInvocation) async throws -> OwnedBytes? {
        throw CancellationError()
    }

    func shutdown() async {}
}

private actor BlockingParticipantEndpoint: ParticipantEndpoint {
    nonisolated let descriptor: ParticipantDescriptor

    private var invocationContinuation: CheckedContinuation<
        OwnedBytes?,
        any Error
    >?
    private var invocationStarted = false
    private var invocationStartWaiters: [CheckedContinuation<Void, Never>] = []
    private var shutdownStarted = false
    private var shutdownStartWaiters: [CheckedContinuation<Void, Never>] = []
    private var invocationDrainWaiter: CheckedContinuation<Void, Never>?

    init(id: ParticipantID) {
        let contract = CapabilityContract(
            id: TestParticipantEndpoint.capability,
            input: TestParticipantEndpoint.representation,
            output: TestParticipantEndpoint.representation
        )
        self.descriptor = ParticipantDescriptor(
            id: id,
            kind: .agent,
            representations: [TestParticipantEndpoint.representation],
            capabilityContracts: [contract]
        )
    }

    func invoke(_ invocation: SymbioInvocation) async throws -> OwnedBytes? {
        invocationStarted = true
        let waiters = invocationStartWaiters
        invocationStartWaiters.removeAll()
        for waiter in waiters {
            waiter.resume()
        }
        let result = try await withCheckedThrowingContinuation {
            continuation in
            invocationContinuation = continuation
        }
        let drainWaiter = invocationDrainWaiter
        invocationDrainWaiter = nil
        drainWaiter?.resume()
        return result
    }

    func shutdown() async {
        shutdownStarted = true
        let startWaiters = shutdownStartWaiters
        shutdownStartWaiters.removeAll()
        for waiter in startWaiters {
            waiter.resume()
        }
        let continuation = invocationContinuation
        invocationContinuation = nil
        continuation?.resume(returning: OwnedBytes(
            consuming: Array("late".utf8)
        ))
        guard invocationStarted else {
            return
        }
        await withCheckedContinuation { continuation in
            invocationDrainWaiter = continuation
        }
    }

    func waitUntilInvocationStarts() async {
        guard !invocationStarted else {
            return
        }
        await withCheckedContinuation { continuation in
            invocationStartWaiters.append(continuation)
        }
    }

    func waitUntilShutdownStarts() async {
        guard !shutdownStarted else {
            return
        }
        await withCheckedContinuation { continuation in
            shutdownStartWaiters.append(continuation)
        }
    }
}

private actor CancellationObservingParticipantEndpoint: ParticipantEndpoint {
    nonisolated let descriptor: ParticipantDescriptor

    private var invocationStarted = false
    private var invocationStartWaiters: [CheckedContinuation<Void, Never>] = []
    private var cancellationObserved = false
    private var cancellationWaiters: [CheckedContinuation<Void, Never>] = []

    init(id: ParticipantID) {
        let contract = CapabilityContract(
            id: TestParticipantEndpoint.capability,
            input: TestParticipantEndpoint.representation,
            output: TestParticipantEndpoint.representation
        )
        self.descriptor = ParticipantDescriptor(
            id: id,
            kind: .agent,
            representations: [TestParticipantEndpoint.representation],
            capabilityContracts: [contract]
        )
    }

    func invoke(_ invocation: SymbioInvocation) async throws -> OwnedBytes? {
        invocationStarted = true
        let startWaiters = invocationStartWaiters
        invocationStartWaiters.removeAll()
        for waiter in startWaiters {
            waiter.resume()
        }

        do {
            try await Task.sleep(for: .seconds(60))
            return invocation.envelope.arguments
        } catch is CancellationError {
            cancellationObserved = true
            let waiters = cancellationWaiters
            cancellationWaiters.removeAll()
            for waiter in waiters {
                waiter.resume()
            }
            throw CancellationError()
        }
    }

    func shutdown() async {}

    func waitUntilInvocationStarts() async {
        guard !invocationStarted else {
            return
        }
        await withCheckedContinuation { continuation in
            invocationStartWaiters.append(continuation)
        }
    }

    func waitUntilCancellationIsObserved() async {
        guard !cancellationObserved else {
            return
        }
        await withCheckedContinuation { continuation in
            cancellationWaiters.append(continuation)
        }
    }
}

private actor TestSymbioLink: SymbioLink {
    private enum Failure: Error {
        case synchronization
        case shutdown
        case stopped
    }

    private var started = false
    private var finished = false
    private var catalogs: [[ParticipantDescriptor]] = []
    private var shouldFailNextSynchronization = false
    private var remainingShutdownFailures: Int
    private var shutdownAttempts = 0
    private var events: [SymbioLinkEvent] = []
    private var eventWaiter: CheckedContinuation<SymbioLinkEvent?, any Error>?
    private var shouldCancelNextReceive = false
    private var replies: [SymbioInvocationReply] = []
    private var replyWaiter: CheckedContinuation<SymbioInvocationReply, Never>?
    private var invokedPeerID: TransportPeerID?
    private let blockRepliesUntilShutdown: Bool
    private let blockInvocationsUntilReleased: Bool
    private let blockShutdownUntilReleased: Bool
    private var sendStarted = false
    private var sendStartWaiter: CheckedContinuation<Void, Never>?
    private var blockedSendWaiter: CheckedContinuation<Void, any Error>?
    private var invocationStarted = false
    private var invocationStartWaiter: CheckedContinuation<Void, Never>?
    private var blockedInvocationWaiter: CheckedContinuation<Void, any Error>?
    private var shouldBlockNextSynchronization = false
    private var synchronizationStarted = false
    private var synchronizationStartWaiter: CheckedContinuation<Void, Never>?
    private var blockedSynchronizationWaiter: CheckedContinuation<Void, any Error>?
    private var shutdownStarted = false
    private var shutdownStartWaiters: [CheckedContinuation<Void, Never>] = []
    private var blockedShutdownWaiter: CheckedContinuation<Void, Never>?
    private var shutdownObservedCancellation: Bool?

    init(
        shutdownFailures: Int = 0,
        blockRepliesUntilShutdown: Bool = false,
        blockInvocationsUntilReleased: Bool = false,
        blockShutdownUntilReleased: Bool = false
    ) {
        self.remainingShutdownFailures = shutdownFailures
        self.blockRepliesUntilShutdown = blockRepliesUntilShutdown
        self.blockInvocationsUntilReleased = blockInvocationsUntilReleased
        self.blockShutdownUntilReleased = blockShutdownUntilReleased
    }

    func start() async throws {
        started = true
    }

    func synchronizeLocalParticipants(
        _ descriptors: [ParticipantDescriptor]
    ) async throws {
        if shouldFailNextSynchronization {
            shouldFailNextSynchronization = false
            throw Failure.synchronization
        }
        catalogs.append(descriptors)
        if shouldBlockNextSynchronization {
            shouldBlockNextSynchronization = false
            synchronizationStarted = true
            let waiter = synchronizationStartWaiter
            synchronizationStartWaiter = nil
            waiter?.resume()
            try await withCheckedThrowingContinuation { continuation in
                blockedSynchronizationWaiter = continuation
            }
        }
    }

    func receive() async throws -> SymbioLinkEvent? {
        if shouldCancelNextReceive {
            shouldCancelNextReceive = false
            throw CancellationError()
        }
        if !events.isEmpty {
            return events.removeFirst()
        }
        if finished {
            return nil
        }
        return try await withCheckedThrowingContinuation { continuation in
            eventWaiter = continuation
        }
    }

    func invoke(
        _ envelope: SymbioInvocationEnvelope,
        on transportPeerID: TransportPeerID,
        timeout: Duration
    ) async throws -> SymbioInvocationReply {
        invokedPeerID = transportPeerID
        if blockInvocationsUntilReleased {
            invocationStarted = true
            let waiter = invocationStartWaiter
            invocationStartWaiter = nil
            waiter?.resume()
            try await withCheckedThrowingContinuation { continuation in
                blockedInvocationWaiter = continuation
            }
        }
        return .success(
            invocationID: envelope.invocationID,
            result: envelope.arguments
        )
    }

    func send(
        _ reply: SymbioInvocationReply,
        to context: SymbioReplyContext
    ) async throws {
        if blockRepliesUntilShutdown {
            sendStarted = true
            let waiter = sendStartWaiter
            sendStartWaiter = nil
            waiter?.resume()
            try await withCheckedThrowingContinuation { continuation in
                blockedSendWaiter = continuation
            }
        }
        if let replyWaiter {
            self.replyWaiter = nil
            replyWaiter.resume(returning: reply)
        } else {
            replies.append(reply)
        }
    }

    func shutdown() async throws {
        shutdownAttempts += 1
        if blockShutdownUntilReleased {
            shutdownStarted = true
            let startWaiters = shutdownStartWaiters
            shutdownStartWaiters.removeAll()
            for waiter in startWaiters {
                waiter.resume()
            }
            await withCheckedContinuation { continuation in
                blockedShutdownWaiter = continuation
            }
        }
        shutdownObservedCancellation = Task.isCancelled
        let sendWaiter = blockedSendWaiter
        blockedSendWaiter = nil
        sendWaiter?.resume(throwing: Failure.stopped)
        let invocationWaiter = blockedInvocationWaiter
        blockedInvocationWaiter = nil
        invocationWaiter?.resume(throwing: Failure.stopped)
        let synchronizationWaiter = blockedSynchronizationWaiter
        blockedSynchronizationWaiter = nil
        synchronizationWaiter?.resume(throwing: Failure.stopped)
        if remainingShutdownFailures > 0 {
            remainingShutdownFailures -= 1
            let waiter = eventWaiter
            eventWaiter = nil
            waiter?.resume(throwing: Failure.shutdown)
            throw Failure.shutdown
        }
        finished = true
        let waiter = eventWaiter
        eventWaiter = nil
        waiter?.resume(returning: nil)
    }

    func emit(_ event: SymbioLinkEvent) {
        if let eventWaiter {
            self.eventWaiter = nil
            eventWaiter.resume(returning: event)
        } else {
            events.append(event)
        }
    }

    func cancelReceiveUnexpectedly() {
        if let eventWaiter {
            self.eventWaiter = nil
            eventWaiter.resume(throwing: CancellationError())
        } else {
            shouldCancelNextReceive = true
        }
    }

    func nextReply() async -> SymbioInvocationReply {
        if !replies.isEmpty {
            return replies.removeFirst()
        }
        return await withCheckedContinuation { continuation in
            replyWaiter = continuation
        }
    }

    func lastInvokedPeerID() -> TransportPeerID? {
        invokedPeerID
    }

    func waitUntilSendStarts() async {
        guard !sendStarted else {
            return
        }
        await withCheckedContinuation { continuation in
            sendStartWaiter = continuation
        }
    }

    func waitUntilInvocationStarts() async {
        guard !invocationStarted else {
            return
        }
        await withCheckedContinuation { continuation in
            invocationStartWaiter = continuation
        }
    }

    func releaseInvocation() {
        let waiter = blockedInvocationWaiter
        blockedInvocationWaiter = nil
        waiter?.resume()
    }

    func synchronizedParticipantIDs() -> [[ParticipantID]] {
        catalogs.map { catalog in
            catalog.map(\.id)
        }
    }

    func failNextSynchronization() {
        shouldFailNextSynchronization = true
    }

    func blockNextSynchronization() {
        shouldBlockNextSynchronization = true
        synchronizationStarted = false
    }

    func waitUntilSynchronizationStarts() async {
        guard !synchronizationStarted else {
            return
        }
        await withCheckedContinuation { continuation in
            synchronizationStartWaiter = continuation
        }
    }

    func shutdownAttemptCount() -> Int {
        shutdownAttempts
    }

    func waitUntilShutdownStarts() async {
        guard !shutdownStarted else {
            return
        }
        await withCheckedContinuation { continuation in
            shutdownStartWaiters.append(continuation)
        }
    }

    func releaseShutdown() {
        let waiter = blockedShutdownWaiter
        blockedShutdownWaiter = nil
        waiter?.resume()
    }

    func shutdownObservedCallerCancellation() -> Bool? {
        shutdownObservedCancellation
    }
}

private struct PartialPolicyAuthorizer: PolicyAuthorizer {
    func authorize(_ request: PolicyRequest) async -> PolicyDecision {
        PolicyDecision(
            state: .approved,
            policyIDs: ["policy.audit"]
        )
    }
}

private actor BlockingPolicyAuthorizer: PolicyAuthorizer {
    private var started = false
    private var startWaiters: [CheckedContinuation<Void, Never>] = []
    private var releaseContinuation: CheckedContinuation<Void, Never>?

    func authorize(_ request: PolicyRequest) async -> PolicyDecision {
        started = true
        let waiters = startWaiters
        startWaiters.removeAll()
        for waiter in waiters {
            waiter.resume()
        }
        await withCheckedContinuation { continuation in
            releaseContinuation = continuation
        }
        return PolicyDecision(
            state: .approved,
            policyIDs: request.policyIDs
        )
    }

    func waitUntilStarted() async {
        guard !started else {
            return
        }
        await withCheckedContinuation { continuation in
            startWaiters.append(continuation)
        }
    }

    func release() {
        let continuation = releaseContinuation
        releaseContinuation = nil
        continuation?.resume()
    }
}

private struct DelayedInboundInvocationAuthorizer: InboundInvocationAuthorizer {
    let delay: Duration

    func authorize(
        _ request: InboundInvocationRequest
    ) async throws -> InboundInvocationDecision {
        try await Task.sleep(for: delay)
        return .allow
    }
}

private func makeRuntime(
    link: TestSymbioLink,
    inboundAuthorizer: any InboundInvocationAuthorizer = RejectingInboundInvocationAuthorizer(),
    maximumInboundExecutionDuration: Duration = .seconds(30)
) throws -> SymbioRuntime {
    try SymbioRuntime(
        identity: ParticipantDescriptor(id: "runtime.local", kind: .service),
        link: link,
        claimVerifier: PinnedParticipantClaimVerifier(pinsByPeerID: [
            "transport.remote": [.init(
                participantID: "worker.remote",
                authenticationMethod: "test",
                authenticationSubject: "authenticated.remote"
            )]
        ]),
        inboundAuthorizer: inboundAuthorizer,
        maximumInboundExecutionDuration: maximumInboundExecutionDuration
    )
}

private func makeClaim() -> SymbioPeerClaim {
    let contract = CapabilityContract(
        id: TestParticipantEndpoint.capability,
        input: TestParticipantEndpoint.representation,
        output: TestParticipantEndpoint.representation
    )
    return SymbioPeerClaim(
        transportPeerID: "transport.remote",
        descriptor: ParticipantDescriptor(
            id: "worker.remote",
            kind: .agent,
            representations: [TestParticipantEndpoint.representation],
            capabilityContracts: [contract]
        ),
        authentication: SymbioPeerAuthentication(
            method: "test",
            subject: "authenticated.remote"
        )
    )
}

private func makeInboundEnvelope(
    recipientID: ParticipantID
) -> SymbioInvocationEnvelope {
    SymbioInvocationEnvelope(
        senderID: "worker.remote",
        recipientID: recipientID,
        capability: TestParticipantEndpoint.capability,
        representation: TestParticipantEndpoint.representation,
        arguments: OwnedBytes(consuming: Array("request".utf8)),
        executionBudget: .seconds(1)
    )
}
