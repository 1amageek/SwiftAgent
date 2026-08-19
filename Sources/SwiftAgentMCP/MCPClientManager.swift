import Foundation
import SwiftAgent

/// Owns a named set of MCP connections and serializes lifecycle changes per server.
public actor MCPClientManager {
    private var clients: [String: MCPClient] = [:]
    private var retiredClients: [String: [MCPClient]] = [:]
    private var serverConfigs: [String: MCPServerConfig] = [:]
    private var disabledServers: Set<String> = []
    private var transitioningServers: Set<String> = []
    private var isBulkTransition = false
    private var catalogGeneration = UUID()

    public init() {}

    public static func load(from configURL: URL) async throws -> MCPClientManager {
        let configuration = try MCPConfiguration.load(from: configURL)
            .expandEnvironmentVariables()
        return try await load(configuration: configuration)
    }

    public static func load(from jsonData: Data) async throws -> MCPClientManager {
        let configuration = try MCPConfiguration.load(from: jsonData)
            .expandEnvironmentVariables()
        return try await load(configuration: configuration)
    }

    public static func load(searchPaths: [String]) async throws -> MCPClientManager {
        guard let configuration = try MCPConfiguration.load(
            searchPaths: searchPaths
        ) else {
            return MCPClientManager()
        }
        return try await load(
            configuration: configuration.expandEnvironmentVariables()
        )
    }

    public func connect(config: MCPServerConfig) async throws {
        try beginTransition(for: config.name)
        defer { endTransition(for: config.name) }
        guard !disabledServers.contains(config.name) else {
            throw MCPClientError.disabledServer(config.name)
        }
        try await replaceConnection(with: config)
    }

    public func disconnect(serverName: String) async throws {
        try beginTransition(for: serverName)
        defer { endTransition(for: serverName) }
        guard allServers.contains(serverName) else {
            throw MCPClientError.serverNotFound(serverName)
        }
        try await disconnectOwnedClient(serverName: serverName)
        try await cleanupRetiredClients(serverName: serverName)
    }

    public func disconnectAll() async throws {
        guard !isBulkTransition, transitioningServers.isEmpty else {
            throw MCPClientError.serverTransitionInProgress(
                transitioningServers.sorted().first ?? "all"
            )
        }
        isBulkTransition = true
        catalogGeneration = UUID()
        defer { isBulkTransition = false }

        var failures: [String] = []
        let activeNames = clients.keys.sorted()
        for name in activeNames {
            do {
                try await disconnectOwnedClient(serverName: name)
            } catch {
                failures.append("\(name): \(error.localizedDescription)")
            }
        }
        let retiredNames = retiredClients.keys.sorted()
        for name in retiredNames {
            do {
                try await cleanupRetiredClients(serverName: name)
            } catch {
                failures.append("\(name) retired: \(error.localizedDescription)")
            }
        }
        if !failures.isEmpty {
            throw MCPClientError.multipleDisconnectFailures(failures)
        }
    }

    public func reconnect(serverName: String) async throws {
        try beginTransition(for: serverName)
        defer { endTransition(for: serverName) }
        guard !disabledServers.contains(serverName) else {
            throw MCPClientError.disabledServer(serverName)
        }
        guard let config = serverConfigs[serverName] else {
            throw MCPClientError.serverNotFound(serverName)
        }
        try await replaceConnection(with: config)
    }

    public func enable(serverName: String) async throws {
        try beginTransition(for: serverName)
        defer { endTransition(for: serverName) }
        guard let config = serverConfigs[serverName] else {
            throw MCPClientError.serverNotFound(serverName)
        }
        if let client = clients[serverName] {
            let lifecycle = await client.lifecycleSnapshot()
            if !lifecycle.isConnected {
                try await disconnectOwnedClient(serverName: serverName)
            }
        }
        if clients[serverName] == nil {
            let client = try await MCPClient.connect(config: config)
            clients[serverName] = client
        }
        disabledServers.remove(serverName)
    }

    public func disable(serverName: String) async throws {
        try beginTransition(for: serverName)
        defer { endTransition(for: serverName) }
        guard serverConfigs[serverName] != nil || clients[serverName] != nil else {
            throw MCPClientError.serverNotFound(serverName)
        }
        disabledServers.insert(serverName)
        try await disconnectOwnedClient(serverName: serverName)
        try await cleanupRetiredClients(serverName: serverName)
    }

    public func isEnabled(serverName: String) -> Bool {
        serverConfigs[serverName] != nil
            && !disabledServers.contains(serverName)
    }

    public func isConnected(serverName: String) async -> Bool {
        guard !isBulkTransition,
              !disabledServers.contains(serverName),
              !transitioningServers.contains(serverName),
              let client = clients[serverName] else {
            return false
        }
        let lifecycle = await client.lifecycleSnapshot()
        guard clients[serverName] === client,
              !isBulkTransition,
              !disabledServers.contains(serverName),
              !transitioningServers.contains(serverName) else {
            return false
        }
        return lifecycle.isConnected
    }

    func connectedClientSnapshot() async -> [(name: String, client: MCPClient)] {
        guard !isBulkTransition else {
            return []
        }
        let unavailable = disabledServers.union(transitioningServers)
        let candidates = clients
            .filter { !unavailable.contains($0.key) }
            .sorted { $0.key < $1.key }
            .map {
                (name: $0.key, client: $0.value)
            }
        var connected: [(name: String, client: MCPClient)] = []
        connected.reserveCapacity(candidates.count)
        for candidate in candidates {
            let lifecycle = await candidate.client.lifecycleSnapshot()
            if lifecycle.isConnected,
               clients[candidate.name] === candidate.client,
               !isBulkTransition,
               !disabledServers.contains(candidate.name),
               !transitioningServers.contains(candidate.name) {
                connected.append(candidate)
            }
        }
        return connected
    }

    public func allTools() async throws -> [MCPDiscoveredTool] {
        let expectedGeneration = catalogGeneration
        try requireNoCatalogTransition()
        let snapshot = await connectedClientSnapshot()
        try requireStableCatalog(expectedGeneration)
        var tools: [MCPDiscoveredTool] = []
        for entry in snapshot {
            let discovered = try await entry.client.discoveredTools()
            try requireStableCatalog(expectedGeneration)
            try await validateOwnedConnectedClient(entry)
            tools.append(contentsOf: discovered)
        }
        try requireStableCatalog(expectedGeneration)
        return tools
    }

    public func allSwiftAgentTools() async throws -> [any SwiftAgent.Tool] {
        try await allTools().swiftAgentTools()
    }

    public func tools(from serverName: String) async throws -> [MCPDiscoveredTool] {
        let expectedGeneration = catalogGeneration
        guard !isBulkTransition,
              let client = clients[serverName],
              !disabledServers.contains(serverName),
              !transitioningServers.contains(serverName) else {
            if serverConfigs[serverName] != nil {
                throw MCPClientError.notConnected(server: serverName)
            }
            throw MCPClientError.serverNotFound(serverName)
        }
        let lifecycle = await client.lifecycleSnapshot()
        guard lifecycle.isConnected,
              clients[serverName] === client,
              !isBulkTransition,
              !disabledServers.contains(serverName),
              !transitioningServers.contains(serverName) else {
            throw MCPClientError.notConnected(server: serverName)
        }
        let tools = try await client.discoveredTools()
        try requireStableCatalog(expectedGeneration)
        try await validateOwnedConnectedClient((
            name: serverName,
            client: client
        ))
        return tools
    }

    public func swiftAgentTools(
        from serverName: String
    ) async throws -> [any SwiftAgent.Tool] {
        try await tools(from: serverName).swiftAgentTools()
    }

    public func connectedServerNames() async -> [String] {
        let connected = await connectedClientSnapshot()
        return connected.map { $0.name }
    }

    public var allServers: [String] {
        Set(clients.keys)
            .union(retiredClients.keys)
            .union(disabledServers)
            .union(serverConfigs.keys)
            .sorted()
    }

    public var disabledServerNames: [String] {
        disabledServers.sorted()
    }

    public func connectedServerCount() async -> Int {
        let connected = await connectedClientSnapshot()
        return connected.count
    }

    public func serverStatuses() async -> [MCPServerStatus] {
        let names = allServers
        var statuses: [MCPServerStatus] = []
        statuses.reserveCapacity(names.count)
        for name in names {
            var lifecycle: MCPClientLifecycleSnapshot?
            while true {
                let candidate = clients[name]
                let snapshot = await candidate?.lifecycleSnapshot()
                let current = clients[name]
                switch (candidate, current) {
                case (.none, .none):
                    lifecycle = nil
                    break
                case (.some(let candidate), .some(let current))
                    where candidate === current:
                    lifecycle = snapshot
                    break
                default:
                    continue
                }
                break
            }
            guard allServers.contains(name) else {
                continue
            }
            statuses.append(MCPServerStatus(
                name: name,
                isConnected: lifecycle?.isConnected == true
                    && !isBulkTransition
                    && !disabledServers.contains(name)
                    && !transitioningServers.contains(name),
                isEnabled: serverConfigs[name] != nil
                    && !disabledServers.contains(name),
                isTransitioning: isBulkTransition
                    || transitioningServers.contains(name),
                hasPendingCleanup: lifecycle?.requiresCleanup == true
                    || retiredClients[name]?.isEmpty == false
            ))
        }
        return statuses
    }

    public func addServer(config: MCPServerConfig) throws {
        guard !isBulkTransition,
              !transitioningServers.contains(config.name) else {
            throw MCPClientError.serverTransitionInProgress(config.name)
        }
        guard serverConfigs[config.name] == nil,
              clients[config.name] == nil,
              retiredClients[config.name] == nil else {
            throw MCPClientError.duplicateServer(config.name)
        }
        catalogGeneration = UUID()
        serverConfigs[config.name] = config
    }

    public func removeServer(serverName: String) async throws {
        try beginTransition(for: serverName)
        defer { endTransition(for: serverName) }
        guard serverConfigs[serverName] != nil || clients[serverName] != nil else {
            throw MCPClientError.serverNotFound(serverName)
        }
        try await disconnectOwnedClient(serverName: serverName)
        try await cleanupRetiredClients(serverName: serverName)
        serverConfigs.removeValue(forKey: serverName)
        disabledServers.remove(serverName)
    }

    private func replaceConnection(with config: MCPServerConfig) async throws {
        let replacement = try await MCPClient.connect(config: config)
        let previous = clients.updateValue(replacement, forKey: config.name)
        serverConfigs[config.name] = config
        guard let previous else {
            return
        }
        do {
            try await previous.disconnect()
        } catch {
            retiredClients[config.name, default: []].append(previous)
            throw MCPClientError.connectionReplacementCleanupFailed(
                server: config.name,
                cleanup: error.localizedDescription
            )
        }
    }

    private func disconnectOwnedClient(serverName: String) async throws {
        guard let client = clients[serverName] else {
            return
        }
        try await client.disconnect()
        clients.removeValue(forKey: serverName)
    }

    private func cleanupRetiredClients(serverName: String) async throws {
        guard let retired = retiredClients[serverName], !retired.isEmpty else {
            retiredClients.removeValue(forKey: serverName)
            return
        }
        var remaining: [MCPClient] = []
        var failures: [String] = []
        for client in retired {
            do {
                try await client.disconnect()
            } catch {
                remaining.append(client)
                failures.append(error.localizedDescription)
            }
        }
        if remaining.isEmpty {
            retiredClients.removeValue(forKey: serverName)
        } else {
            retiredClients[serverName] = remaining
        }
        if !failures.isEmpty {
            throw MCPClientError.multipleDisconnectFailures(failures)
        }
    }

    private func beginTransition(for serverName: String) throws {
        guard !isBulkTransition,
              transitioningServers.insert(serverName).inserted else {
            throw MCPClientError.serverTransitionInProgress(serverName)
        }
        catalogGeneration = UUID()
    }

    func validateOwnedConnectedClient(
        _ entry: (name: String, client: MCPClient)
    ) async throws {
        guard !isBulkTransition,
              clients[entry.name] === entry.client,
              !disabledServers.contains(entry.name),
              !transitioningServers.contains(entry.name) else {
            throw MCPClientError.notConnected(server: entry.name)
        }
        let lifecycle = await entry.client.lifecycleSnapshot()
        guard lifecycle.isConnected,
              !isBulkTransition,
              clients[entry.name] === entry.client,
              !disabledServers.contains(entry.name),
              !transitioningServers.contains(entry.name) else {
            throw MCPClientError.notConnected(server: entry.name)
        }
    }

    func requireNoCatalogTransition() throws {
        guard !isBulkTransition, transitioningServers.isEmpty else {
            throw MCPClientError.serverTransitionInProgress(
                transitioningServers.sorted().first ?? "all"
            )
        }
    }

    func requireStableCatalog(_ expectedGeneration: UUID) throws {
        guard catalogGeneration == expectedGeneration,
              !isBulkTransition,
              transitioningServers.isEmpty else {
            throw MCPClientError.serverCatalogChanged
        }
    }

    func currentCatalogGeneration() -> UUID {
        catalogGeneration
    }

    private func endTransition(for serverName: String) {
        if transitioningServers.remove(serverName) != nil {
            catalogGeneration = UUID()
        }
    }

    private func registerDisabled(config: MCPServerConfig) {
        catalogGeneration = UUID()
        serverConfigs[config.name] = config
        disabledServers.insert(config.name)
    }

    private static func load(
        configuration: MCPConfiguration
    ) async throws -> MCPClientManager {
        let manager = MCPClientManager()
        do {
            for resolved in try configuration.resolvedServerConfigs() {
                if resolved.isEnabled {
                    try await manager.connect(config: resolved.config)
                } else {
                    await manager.registerDisabled(config: resolved.config)
                }
            }
            return manager
        } catch {
            do {
                try await manager.disconnectAll()
            } catch let cleanupError {
                throw MCPClientError.loadAndCleanupFailed(
                    load: error.localizedDescription,
                    cleanup: cleanupError.localizedDescription,
                    recovery: manager
                )
            }
            throw error
        }
    }
}
