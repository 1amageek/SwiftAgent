// MARK: - Community
// The community of agents that this agent can interact with
// Wraps SymbioActorSystem and provides a high-level API for agent interaction

import Foundation
import SwiftAgent
import DiscoveryCore
import Distributed

// MARK: - Member

/// A member of the community
/// Represents another agent that this agent can potentially interact with
public struct Member: Identifiable, Hashable, Sendable, Codable {
    /// Unique identifier for this member
    public let id: String

    /// Display name (optional)
    public let name: String?

    /// What signals this member can receive
    public let accepts: Set<String>

    /// What capabilities this member provides
    public let provides: Set<String>

    /// Whether this member is currently available
    public private(set) var isAvailable: Bool

    /// Additional metadata
    public let metadata: [String: String]

    public init(
        id: String,
        name: String? = nil,
        accepts: Set<String> = [],
        provides: Set<String> = [],
        isAvailable: Bool = true,
        metadata: [String: String] = [:]
    ) {
        self.id = id
        self.name = name
        self.accepts = accepts
        self.provides = provides
        self.isAvailable = isAvailable
        self.metadata = metadata
    }

    /// Check if this member can receive a specific signal type
    public func canReceive(_ perception: String) -> Bool {
        accepts.contains(perception)
    }

    /// Check if this member provides a specific capability
    public func canProvide(_ capability: String) -> Bool {
        provides.contains(capability)
    }

    /// Create an unavailable copy of this member
    public func unavailable() -> Member {
        var copy = self
        copy.isAvailable = false
        return copy
    }

    /// Create an available copy of this member
    public func available() -> Member {
        var copy = self
        copy.isAvailable = true
        return copy
    }
}

// MARK: - CommunityChange

/// Changes in the community
public enum CommunityChange: Sendable {
    /// A new member joined the community
    case joined(Member)

    /// A member left the community
    case left(Member)

    /// A member's information was updated
    case updated(Member)

    /// A member became available
    case becameAvailable(Member)

    /// A member became unavailable
    case becameUnavailable(Member)
}

// MARK: - Community

/// The community of agents
///
/// Community provides a simple interface for agents to find and interact
/// with other agents. It wraps SymbioActorSystem and abstracts away all
/// the complexity of discovery, connection management, and transport details.
///
/// From the Agent's perspective, they simply ask:
/// - "Who can receive this signal?"
/// - "Who provides this capability?"
/// - "Send this to that member"
///
/// Usage:
/// ```swift
/// let actorSystem = SymbioActorSystem()
/// let community = Community(actorSystem: actorSystem)
/// try await community.start()
///
/// // Spawn an agent
/// let worker = try await community.spawn {
///     WorkerAgent(community: community, actorSystem: actorSystem)
/// }
///
/// // Send a signal
/// try await community.send(MySignal(), to: worker, perception: "work")
/// ```
public actor Community {

    // MARK: - Properties

    /// The actor system for distributed communication
    public let actorSystem: SymbioActorSystem

    /// The peer connector for discovery
    private let connector: PeerConnector

    /// Cached members
    private var memberCache: [String: Member] = [:]

    /// Local agent IDs (for tracking which members are local)
    private var localAgentIDs: Set<String> = []

    /// Local agent references (to prevent deallocation)
    private var localAgentRefs: [String: any DistributedActor] = [:]

    /// Registered method names per agent (for cleanup on terminate)
    private var registeredMethods: [String: [String]] = [:]

    /// Change continuation for broadcasting changes
    private var changeContinuation: AsyncStream<CommunityChange>.Continuation?

    /// Changes stream
    private var _changes: AsyncStream<CommunityChange>?

    /// Background task for monitoring discovery
    private var monitorTask: Task<Void, Never>?

    /// This community's self ID
    private let selfID: String = UUID().uuidString

    // MARK: - Initialization

    /// Create a new Community with an actor system
    public init(actorSystem: SymbioActorSystem) {
        self.actorSystem = actorSystem
        self.connector = PeerConnector(
            name: "community-\(UUID().uuidString.prefix(8))",
            perceptions: [],
            capabilities: [],
            displayName: nil,
            metadata: [:]
        )
    }

    /// Create a new Community with configuration
    public init(
        name: String,
        perceptions: [any Perception] = [],
        capabilities: [CapabilityID] = [],
        displayName: String? = nil,
        metadata: [String: String] = [:]
    ) {
        self.actorSystem = SymbioActorSystem()
        self.connector = PeerConnector(
            name: name,
            perceptions: perceptions,
            capabilities: capabilities,
            displayName: displayName,
            metadata: metadata
        )
    }

    // MARK: - Lifecycle

    /// Start the community (begins discovery)
    public func start() async throws {
        // Connect actor system with peer connector
        await actorSystem.setPeerConnector(connector)

        try await connector.start()
        startMonitoring()
    }

    /// Stop the community
    public func stop() async throws {
        monitorTask?.cancel()
        monitorTask = nil

        // Terminate all local agents
        for agentID in localAgentIDs {
            if let member = memberCache[agentID] {
                if let agent = localAgentRefs[agentID] as? Terminatable {
                    await agent.terminate()
                }

                // Unregister methods from actor system
                if let methods = registeredMethods[agentID] {
                    for method in methods {
                        actorSystem.unregisterMethod(method)
                    }
                }

                // Remove from actor system registry
                if let address = try? Address(hexString: agentID) {
                    actorSystem.resignID(address)
                }

                changeContinuation?.yield(.left(member))
            }
        }

        localAgentIDs.removeAll()
        localAgentRefs.removeAll()
        registeredMethods.removeAll()
        memberCache.removeAll()

        try await connector.stop()
    }

    /// Register a transport
    public func register<T: DiscoveryCore.Transport>(_ transport: T) async {
        await connector.register(transport)
    }

    // MARK: - Member Search

    /// Find members who can receive a specific signal type
    /// - Parameter perception: The perception/signal type identifier
    /// - Returns: Array of available members who can receive this signal
    public func whoCanReceive(_ perception: String) -> [Member] {
        memberCache.values
            .filter { $0.isAvailable && $0.canReceive(perception) }
            .sorted { $0.id < $1.id }
    }

    /// Find members who provide a specific capability
    /// - Parameter capability: The capability identifier
    /// - Returns: Array of available members who provide this capability
    public func whoProvides(_ capability: String) -> [Member] {
        memberCache.values
            .filter { $0.isAvailable && $0.canProvide(capability) }
            .sorted { $0.id < $1.id }
    }

    /// Get a specific member by ID
    /// - Parameter id: The member's identifier
    /// - Returns: The member if found
    public func member(id: String) -> Member? {
        memberCache[id]
    }

    /// All members in the community
    public var members: [Member] {
        Array(memberCache.values).sorted { $0.id < $1.id }
    }

    /// All available members
    public var availableMembers: [Member] {
        memberCache.values
            .filter { $0.isAvailable }
            .sorted { $0.id < $1.id }
    }

    // MARK: - Communication

    /// Send a signal to a member
    ///
    /// Routes signals based on member location:
    /// - Local agents: Direct call via distributed actor
    /// - Remote agents: Via PeerConnector (Discovery)
    ///
    /// - Parameters:
    ///   - signal: The signal to send
    ///   - member: The target member
    ///   - perception: The perception identifier
    /// - Returns: Optional response data
    @discardableResult
    public func send<S: Sendable & Codable>(
        _ signal: S,
        to member: Member,
        perception: String
    ) async throws -> Data? {
        guard member.isAvailable else {
            throw CommunityError.memberUnavailable(member.id)
        }

        guard member.canReceive(perception) else {
            throw CommunityError.noAcceptedPerceptions(member.id)
        }

        // Serialize the signal
        let data = try JSONEncoder().encode(signal)

        // Path 1: Local agent - direct call
        if localAgentIDs.contains(member.id),
           let agent = localAgentRefs[member.id] as? any Communicable {
            return try await agent.receive(data, perception: perception)
        }

        // Path 2: Remote agent - via PeerConnector
        let peerID = PeerID(member.id)

        let capabilityString = "\(AgentCapabilityNamespace.perception).\(perception)"
        guard let capabilityID = try? CapabilityID(parsing: capabilityString) else {
            throw CommunityError.invalidCapability(capabilityString)
        }

        let result = try await connector.invoke(
            capabilityID,
            on: peerID,
            arguments: data,
            timeout: .seconds(30)
        )

        if result.success {
            return result.data
        } else if let error = result.error {
            throw CommunityError.invocationFailed(error.message)
        } else {
            throw CommunityError.invocationFailed("Unknown error")
        }
    }

    /// Invoke a capability on a member
    /// - Parameters:
    ///   - capability: The capability to invoke
    ///   - member: The target member
    ///   - arguments: The arguments to pass
    /// - Returns: The result data
    public func invoke(
        _ capability: String,
        on member: Member,
        with arguments: Data
    ) async throws -> Data {
        guard member.isAvailable else {
            throw CommunityError.memberUnavailable(member.id)
        }

        guard member.canProvide(capability) else {
            throw CommunityError.memberDoesNotProvide(member.id, capability)
        }

        let peerID = PeerID(member.id)

        guard let capabilityID = try? CapabilityID(parsing: capability) else {
            throw CommunityError.invalidCapability(capability)
        }

        let result = try await connector.invoke(
            capabilityID,
            on: peerID,
            arguments: arguments,
            timeout: .seconds(30)
        )

        if result.success, let data = result.data {
            return data
        } else if let error = result.error {
            throw CommunityError.invocationFailed(error.message)
        } else {
            throw CommunityError.invocationFailed("Unknown error")
        }
    }

    // MARK: - Local Agent Management

    /// Spawn a local agent within this community
    ///
    /// Creates a distributed actor instance using the provided factory.
    /// The agent is automatically registered with the actor system via
    /// `actorReady()` when the distributed actor is initialized.
    ///
    /// - Parameter factory: Async factory closure that creates the agent
    /// - Returns: Member representing the spawned agent
    ///
    /// Usage:
    /// ```swift
    /// let worker = try await community.spawn {
    ///     WorkerAgent(community: community, actorSystem: actorSystem)
    /// }
    /// ```
    @discardableResult
    public func spawn<A: Communicable>(
        _ factory: @escaping () async throws -> A
    ) async throws -> Member {
        // 1. Create the agent instance (actorReady() is called automatically)
        let agent = try await factory()

        // 2. Get the agent ID from the distributed actor
        let agentID = agent.id.hexString

        // 3. Extract perceptions from agent (nonisolated access)
        let perceptions = agent.perceptions
        let accepts = Set(perceptions.map { $0.identifier })

        // 4. Create Member for this agent
        let member = Member(
            id: agentID,
            name: nil,
            accepts: accepts,
            provides: [],
            isAvailable: true,
            metadata: ["location": "local"]
        )

        // 5. Store references
        localAgentIDs.insert(agentID)
        localAgentRefs[agentID] = agent

        // 6. Register methods with SymbioActorSystem for remote invocation routing
        var methods: [String] = []
        for perception in perceptions {
            let methodName = "\(AgentCapabilityNamespace.perception).\(perception.identifier)"
            actorSystem.registerMethod(methodName, for: agent.id)
            methods.append(methodName)
        }
        registeredMethods[agentID] = methods

        // 7. Add to member cache
        memberCache[agentID] = member

        // 8. Broadcast .joined event
        changeContinuation?.yield(.joined(member))

        return member
    }

    /// Terminate a local agent
    ///
    /// Stops the agent and removes it from the community.
    /// Only local agents (spawned with `spawn()`) can be terminated.
    /// Remote agents cannot be terminated.
    ///
    /// - Parameter member: The member to terminate
    /// - Throws: CommunityError if the member cannot be terminated
    public func terminate(_ member: Member) async throws {
        let agentID = member.id
        let location = member.metadata["location"]

        // Only local agents can be terminated
        guard location == "local" else {
            throw CommunityError.cannotTerminateRemote(agentID)
        }

        try await terminateLocalAgent(agentID)

        // Remove from member cache
        memberCache.removeValue(forKey: agentID)

        // Broadcast .left event
        changeContinuation?.yield(.left(member))
    }

    /// Terminate a local distributed actor agent
    private func terminateLocalAgent(_ agentID: String) async throws {
        // Verify it's a known local agent
        guard localAgentIDs.contains(agentID) else {
            throw CommunityError.memberNotFound(agentID)
        }

        // Call Terminatable.terminate() if implemented
        if let agent = localAgentRefs[agentID] as? Terminatable {
            await agent.terminate()
        }

        // Unregister methods from actor system
        if let methods = registeredMethods[agentID] {
            for method in methods {
                actorSystem.unregisterMethod(method)
            }
        }
        registeredMethods.removeValue(forKey: agentID)

        // Remove from actor system registry
        if let address = try? Address(hexString: agentID) {
            actorSystem.resignID(address)
        }

        // Remove from storage
        localAgentIDs.remove(agentID)
        localAgentRefs.removeValue(forKey: agentID)
    }

    // MARK: - Changes

    /// Stream of community changes
    ///
    /// **Important**: This stream can only be consumed by a single observer.
    /// Calling this property multiple times returns the same stream instance.
    /// If you need multiple observers, iterate once and broadcast manually.
    ///
    /// Usage:
    /// ```swift
    /// for await change in await community.changes {
    ///     switch change {
    ///     case .joined(let member): print("Joined: \(member.id)")
    ///     case .left(let member): print("Left: \(member.id)")
    ///     default: break
    ///     }
    /// }
    /// ```
    public var changes: AsyncStream<CommunityChange> {
        if let existing = _changes {
            return existing
        }

        let (stream, continuation) = AsyncStream<CommunityChange>.makeStream()
        _changes = stream
        changeContinuation = continuation
        return stream
    }

    // MARK: - Private Methods

    /// Start monitoring for discovered peers
    private func startMonitoring() {
        monitorTask = Task { [weak self] in
            guard let self = self else { return }

            // Periodically refresh discovered peers
            while !Task.isCancelled {
                await self.refreshMembers()
                try? await Task.sleep(for: .seconds(5))
            }
        }
    }

    /// Refresh the member cache from discovery
    private func refreshMembers() async {
        do {
            let stream = await connector.discoverAll(timeout: .seconds(3))

            var discoveredIDs: Set<String> = []

            for try await peer in stream {
                let memberID = peer.peerID.name
                discoveredIDs.insert(memberID)

                let accepts = extractPerceptionIdentifiers(from: peer.accepts)
                let provides = Set(peer.provides.map { $0.fullString })

                // Merge peer metadata with location marker
                var metadata = peer.metadata
                metadata["location"] = "remote"

                let member = Member(
                    id: memberID,
                    name: peer.metadata["name"],
                    accepts: accepts,
                    provides: provides,
                    isAvailable: true,
                    metadata: metadata
                )

                if let existing = memberCache[memberID] {
                    if existing != member {
                        memberCache[memberID] = member
                        changeContinuation?.yield(.updated(member))
                    } else if !existing.isAvailable {
                        memberCache[memberID] = member
                        changeContinuation?.yield(.becameAvailable(member))
                    }
                } else {
                    memberCache[memberID] = member
                    changeContinuation?.yield(.joined(member))
                }
            }

            // Mark members not in discovery as unavailable
            // Skip local agents - they are managed separately
            for (id, member) in memberCache where member.isAvailable && !discoveredIDs.contains(id) {
                // Skip local agents
                guard !localAgentIDs.contains(id) else {
                    continue
                }
                let unavailableMember = member.unavailable()
                memberCache[id] = unavailableMember
                changeContinuation?.yield(.becameUnavailable(unavailableMember))
            }
        } catch {
            // Discovery failed - don't change current state
        }
    }

    /// Extract perception identifiers from capability IDs
    private func extractPerceptionIdentifiers(from capabilityIDs: [CapabilityID]) -> Set<String> {
        let prefix = "\(AgentCapabilityNamespace.perception)."
        var identifiers: Set<String> = []

        for capID in capabilityIDs {
            let fullString = capID.fullString
            if fullString.hasPrefix(prefix) {
                let identifier = String(fullString.dropFirst(prefix.count))
                identifiers.insert(identifier)
            }
        }

        return identifiers
    }
}

// MARK: - CommunityError

/// Errors that can occur in community operations
public enum CommunityError: Error, LocalizedError {
    case memberUnavailable(String)
    case memberDoesNotProvide(String, String)
    case noAcceptedPerceptions(String)
    case invalidCapability(String)
    case invocationFailed(String)
    case cannotTerminateRemote(String)
    case memberNotFound(String)

    public var errorDescription: String? {
        switch self {
        case .memberUnavailable(let id):
            return "Member '\(id)' is not available"
        case .memberDoesNotProvide(let id, let capability):
            return "Member '\(id)' does not provide capability '\(capability)'"
        case .noAcceptedPerceptions(let id):
            return "Member '\(id)' does not accept this perception"
        case .invalidCapability(let capability):
            return "Invalid capability identifier: '\(capability)'"
        case .invocationFailed(let message):
            return "Invocation failed: \(message)"
        case .cannotTerminateRemote(let id):
            return "Cannot terminate remote member '\(id)'. Only local agents can be terminated."
        case .memberNotFound(let id):
            return "Member '\(id)' not found in local agents"
        }
    }
}
