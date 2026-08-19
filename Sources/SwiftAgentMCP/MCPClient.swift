import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif
import MCP
import SwiftAgent

/// Owns one upstream MCP client, its transport, and any spawned server process.
public actor MCPClient {
    private enum State {
        case idle
        case connecting
        case connected
        case transportFailed(String)
        case disconnecting
        case cleanupFailed
        case disconnected
    }

    public nonisolated let name: String
    public private(set) var instructions: String?

    private let config: MCPServerConfig
    private let client: Client
    private let timeout: MCPTimeoutConfig
    private var state: State = .idle
    private var connectionGeneration: UUID?
    private var transport: (any Transport)?
    private var transportOwner: MCPClientTransportOwner?
    private var processLease: MCPProcessLease?
    private var cleanupOperationID: UUID?
    private var cleanupTask: Task<Result<Void, MCPClientError>, Never>?

    private init(config: MCPServerConfig, timeout: MCPTimeoutConfig) {
        self.name = config.name
        self.config = config
        self.timeout = timeout
        self.client = Client(
            name: SwiftAgent.Info.name,
            version: SwiftAgent.Info.version,
            configuration: .strict
        )
    }

    public static func connect(config: MCPServerConfig) async throws -> MCPClient {
        let timeout: MCPTimeoutConfig
        if let configuredTimeout = config.timeout {
            timeout = configuredTimeout
        } else {
            timeout = try MCPTimeoutConfig.fromEnvironment()
        }
        let client = MCPClient(config: config, timeout: timeout)
        try await client.establishConnection()
        return client
    }

    public func disconnect() async throws {
        switch state {
        case .disconnected:
            return
        case .disconnecting:
            do {
                try await cleanupOwnedResources()
                state = .disconnected
            } catch {
                state = .cleanupFailed
                throw error
            }
            return
        case .idle, .connecting, .connected, .transportFailed, .cleanupFailed:
            state = .disconnecting
            connectionGeneration = nil
        }

        do {
            try await cleanupOwnedResources()
            state = .disconnected
        } catch {
            state = .cleanupFailed
            throw error
        }
    }

    func lifecycleSnapshot() async -> MCPClientLifecycleSnapshot {
        await refreshTransportState()
        switch state {
        case .connected:
            return MCPClientLifecycleSnapshot(
                isConnected: true,
                requiresCleanup: false
            )
        case .transportFailed, .disconnecting, .cleanupFailed:
            return MCPClientLifecycleSnapshot(
                isConnected: false,
                requiresCleanup: true
            )
        case .idle, .connecting, .disconnected:
            return MCPClientLifecycleSnapshot(
                isConnected: false,
                requiresCleanup: false
            )
        }
    }

    public func listTools() async throws -> [MCP.Tool] {
        try await requireConnected()
        var tools: [MCP.Tool] = []
        var cursor: String?
        var seen: Set<String> = []

        for _ in 0..<config.paginationPageLimit {
            let request: Request<ListTools>
            if let cursor {
                request = ListTools.request(.init(cursor: cursor))
            } else {
                request = ListTools.request(.init())
            }
            let result = try await executeRequest(
                request,
                operation: "tools/list",
                timeout: timeout.requestExecution
            )
            tools.append(contentsOf: result.tools)
            guard let nextCursor = result.nextCursor else {
                return tools
            }
            guard seen.insert(nextCursor).inserted else {
                throw MCPClientError.paginationCycle(
                    server: name,
                    operation: "tools",
                    cursor: nextCursor
                )
            }
            cursor = nextCursor
        }
        throw MCPClientError.paginationLimitExceeded(
            server: name,
            operation: "tools",
            limit: config.paginationPageLimit
        )
    }

    public func callTool(
        name toolName: String,
        arguments: [String: Value]?
    ) async throws -> MCPToolResult {
        try await requireConnected()
        let request = CallTool.request(.init(name: toolName, arguments: arguments))
        let result = try await executeRequest(
            request,
            operation: "tools/call/\(toolName)",
            timeout: timeout.toolExecution
        )
        return MCPToolResult(
            content: result.content,
            structuredContent: result.structuredContent,
            isError: result.isError ?? false
        )
    }

    public func listResources() async throws -> [Resource] {
        try await requireConnected()
        var resources: [Resource] = []
        var cursor: String?
        var seen: Set<String> = []

        for _ in 0..<config.paginationPageLimit {
            let request: Request<ListResources>
            if let cursor {
                request = ListResources.request(.init(cursor: cursor))
            } else {
                request = ListResources.request(.init())
            }
            let result = try await executeRequest(
                request,
                operation: "resources/list",
                timeout: timeout.requestExecution
            )
            resources.append(contentsOf: result.resources)
            guard let nextCursor = result.nextCursor else {
                return resources
            }
            guard seen.insert(nextCursor).inserted else {
                throw MCPClientError.paginationCycle(
                    server: name,
                    operation: "resources",
                    cursor: nextCursor
                )
            }
            cursor = nextCursor
        }
        throw MCPClientError.paginationLimitExceeded(
            server: name,
            operation: "resources",
            limit: config.paginationPageLimit
        )
    }

    public func readResource(uri: String) async throws -> [Resource.Content] {
        try await requireConnected()
        let result = try await executeRequest(
            ReadResource.request(.init(uri: uri)),
            operation: "resources/read",
            timeout: timeout.requestExecution
        )
        return result.contents
    }

    public func resourceAsText(uri: String) async throws -> String {
        let contents = try await readResource(uri: uri)
        var text: [String] = []
        text.reserveCapacity(contents.count)
        for content in contents {
            guard let value = content.text else {
                throw MCPClientError.nonTextResource(server: name, uri: uri)
            }
            text.append(value)
        }
        return text.joined(separator: "\n")
    }

    public func listPrompts() async throws -> [MCP.Prompt] {
        try await requireConnected()
        var prompts: [MCP.Prompt] = []
        var cursor: String?
        var seen: Set<String> = []

        for _ in 0..<config.paginationPageLimit {
            let request: Request<ListPrompts>
            if let cursor {
                request = ListPrompts.request(.init(cursor: cursor))
            } else {
                request = ListPrompts.request(.init())
            }
            let result = try await executeRequest(
                request,
                operation: "prompts/list",
                timeout: timeout.requestExecution
            )
            prompts.append(contentsOf: result.prompts)
            guard let nextCursor = result.nextCursor else {
                return prompts
            }
            guard seen.insert(nextCursor).inserted else {
                throw MCPClientError.paginationCycle(
                    server: name,
                    operation: "prompts",
                    cursor: nextCursor
                )
            }
            cursor = nextCursor
        }
        throw MCPClientError.paginationLimitExceeded(
            server: name,
            operation: "prompts",
            limit: config.paginationPageLimit
        )
    }

    public func getPrompt(
        name: String,
        arguments: [String: String]?
    ) async throws -> (String?, [MCP.Prompt.Message]) {
        try await requireConnected()
        let result = try await executeRequest(
            GetPrompt.request(.init(name: name, arguments: arguments)),
            operation: "prompts/get/\(name)",
            timeout: timeout.requestExecution
        )
        return (result.description, result.messages)
    }

    private func establishConnection() async throws {
        guard case .idle = state else {
            throw MCPClientError.notConnected(server: name)
        }
        state = .connecting

        do {
            let created = try await makeTransport()
            transport = created.transport
            transportOwner = created.owner
            processLease = created.processLease
            let serverName = name
            let upstreamClient = client
            let startupProcessLease = created.processLease

            let result = try await withMCPDeadline(
                timeout.startup,
                timeoutError: {
                    MCPClientError.connectionTimeout(server: serverName)
                },
                onCancellation: { _ in
                    try await Self.terminateConnection(
                        client: upstreamClient,
                        processLease: startupProcessLease
                    )
                },
                operation: {
                    try await upstreamClient.connect(transport: created.transport)
                }
            )
            if let failure = await created.owner.operationalFailure() {
                throw failure
            }
            instructions = result.instructions
            connectionGeneration = UUID()
            state = .connected
        } catch {
            let connectionError = Self.normalizedCancellation(
                error,
                server: name,
                operation: "connect"
            )
            state = .disconnecting
            connectionGeneration = nil
            do {
                try await cleanupOwnedResources()
                state = .disconnected
            } catch let cleanupError {
                state = .cleanupFailed
                throw MCPClientError.connectionAndCleanupFailed(
                    server: name,
                    connection: connectionError.localizedDescription,
                    cleanup: cleanupError.localizedDescription
                )
            }
            throw connectionError
        }
    }

    private func makeTransport() async throws -> (
        transport: any Transport,
        owner: MCPClientTransportOwner,
        processLease: MCPProcessLease?
    ) {
        let rawTransport: any Transport
        let processLease: MCPProcessLease?
        switch config.transport {
        case .stdio(let command, let arguments, let environment, let workingDirectory):
            #if os(macOS) || os(Linux)
            let launched = try MCPProcessLease.launch(
                serverName: name,
                command: command,
                arguments: arguments,
                environment: environment,
                workingDirectory: workingDirectory
            )
            rawTransport = launched.transport
            processLease = launched.lease
            #else
            throw MCPClientError.processLaunchFailed(
                server: name,
                reason: "Child-process stdio is unavailable on this platform"
            )
            #endif

        case .streamableHTTP(let endpoint, let streaming, let headers):
            let authorizationHeader = config.authorization.staticAuthorizationHeader()
            let configuration = URLSessionConfiguration.ephemeral
            configuration.httpShouldSetCookies = false
            configuration.httpCookieStorage = nil
            configuration.urlCredentialStorage = nil
            configuration.requestCachePolicy = .reloadIgnoringLocalCacheData
            configuration.urlCache = nil
            rawTransport = HTTPClientTransport(
                endpoint: endpoint,
                configuration: configuration,
                streaming: streaming,
                authorizer: config.authorization.makeAuthorizer(),
                requestModifier: { request in
                    var request = request
                    for (name, value) in headers {
                        request.setValue(value, forHTTPHeaderField: name)
                    }
                    if let authorizationHeader {
                        request.setValue(authorizationHeader, forHTTPHeaderField: "Authorization")
                    }
                    return request
                }
            )
            processLease = nil
        }

        let owner = MCPClientTransportOwner(
            serverName: name,
            transport: rawTransport,
            maximumMessageBytes: config.maximumMessageBytes,
            logger: await rawTransport.logger
        )
        return (owner, owner, processLease)
    }

    private func requireConnected() async throws {
        await refreshTransportState()
        if case .transportFailed(let reason) = state {
            throw MCPClientError.transportTerminated(
                server: name,
                reason: reason
            )
        }
        guard case .connected = state, connectionGeneration != nil else {
            throw MCPClientError.notConnected(server: name)
        }
    }

    private func requireConnected(
        generation expectedGeneration: UUID
    ) async throws {
        try await requireConnected()
        guard case .connected = state,
              connectionGeneration == expectedGeneration else {
            throw MCPClientError.notConnected(server: name)
        }
    }

    private func executeRequest<M: MCP.Method>(
        _ request: Request<M>,
        operation: String,
        timeout duration: Duration
    ) async throws -> M.Result {
        try Task.checkCancellation()
        try await requireConnected()
        guard let expectedGeneration = connectionGeneration else {
            throw MCPClientError.notConnected(server: name)
        }
        let context = try await client.send(request)
        let serverName = name
        let connectionOwner = self

        do {
            let result = try await withMCPDeadline(
                duration,
                timeoutError: {
                    MCPClientError.requestTimeout(
                        server: serverName,
                        operation: operation
                    )
                },
                onCancellation: { cancellation in
                    try await connectionOwner.cancelConnectionForRequest(
                        expectedGeneration: expectedGeneration,
                        operation: operation,
                        cancellation: cancellation
                    )
                },
                operation: {
                    try await context.value
                }
            )
            try await requireConnected(generation: expectedGeneration)
            return result
        } catch {
            let requestError = Self.normalizedCancellation(
                error,
                server: name,
                operation: operation
            )
            if Self.requiresForcedDisconnection(requestError),
               shouldFinishForcedDisconnection(
                   expectedGeneration: expectedGeneration
               ) {
                try await finishForcedDisconnection(after: requestError)
            } else {
                await refreshTransportState()
                if case .transportFailed(let reason) = state {
                    throw MCPClientError.transportTerminated(
                        server: name,
                        reason: reason
                    )
                }
            }
            throw requestError
        }
    }

    private func finishForcedDisconnection(
        after operationError: any Error
    ) async throws {
        state = .disconnecting
        connectionGeneration = nil
        do {
            try await cleanupOwnedResources()
            state = .disconnected
        } catch {
            state = .cleanupFailed
            throw MCPClientError.requestCancellationAndCleanupFailed(
                server: name,
                cancellation: operationError.localizedDescription,
                cleanup: error.localizedDescription
            )
        }
    }

    private func cancelConnectionForRequest(
        expectedGeneration: UUID,
        operation: String,
        cancellation: MCPDeadlineCancellation
    ) async throws {
        switch state {
        case .connected:
            guard connectionGeneration == expectedGeneration else {
                return
            }
            state = .disconnecting
            connectionGeneration = nil
        case .transportFailed, .cleanupFailed:
            state = .disconnecting
            connectionGeneration = nil
        case .disconnecting:
            break
        case .disconnected:
            return
        case .idle, .connecting:
            return
        }

        do {
            try await cleanupOwnedResources()
            state = .disconnected
        } catch {
            state = .cleanupFailed
            let reason: String
            switch cancellation {
            case .timedOut:
                reason = "MCP request '\(operation)' exceeded its deadline"
            case .callerCancelled:
                reason = "MCP request '\(operation)' caller was cancelled"
            }
            throw MCPClientError.requestCancellationAndCleanupFailed(
                server: name,
                cancellation: reason,
                cleanup: error.localizedDescription
            )
        }
    }

    private func refreshTransportState() async {
        guard case .connected = state,
              let failure = await transportOwner?.operationalFailure() else {
            return
        }
        connectionGeneration = nil
        state = .transportFailed(failure.localizedDescription)
    }

    private func cleanupOwnedResources() async throws {
        if let cleanupOperationID, let cleanupTask {
            let result = await cleanupTask.value
            finishCleanupOperation(cleanupOperationID)
            try result.get()
            return
        }

        let operationID = UUID()
        let task = Task { [self] () -> Result<Void, MCPClientError> in
            await performOwnedResourceCleanup()
        }
        cleanupOperationID = operationID
        cleanupTask = task

        let result = await task.value
        finishCleanupOperation(operationID)
        try result.get()
    }

    private func performOwnedResourceCleanup() async -> Result<Void, MCPClientError> {
        let lease = processLease
        async let processResult = Self.shutdownProcess(lease)
        await client.disconnect()
        let result = await processResult
        transport = nil
        transportOwner = nil
        switch result {
        case .success:
            processLease = nil
            return .success(())
        case .failure(let error):
            if let clientError = error as? MCPClientError {
                return .failure(clientError)
            }
            return .failure(.processCleanupFailed(
                server: name,
                reasons: [error.localizedDescription]
            ))
        }
    }

    private func finishCleanupOperation(_ operationID: UUID) {
        guard cleanupOperationID == operationID else {
            return
        }
        cleanupOperationID = nil
        cleanupTask = nil
    }

    private static func terminateConnection(
        client: Client,
        processLease: MCPProcessLease?
    ) async throws {
        async let processResult = shutdownProcess(processLease)
        await client.disconnect()
        try await processResult.get()
    }

    private static func shutdownProcess(
        _ processLease: MCPProcessLease?
    ) async -> Result<Void, any Error> {
        #if os(macOS) || os(Linux)
        do {
            try await processLease?.shutdown()
            return .success(())
        } catch {
            return .failure(error)
        }
        #else
        return .success(())
        #endif
    }

    private static func requiresForcedDisconnection(_ error: any Error) -> Bool {
        if error is CancellationError {
            return true
        }
        guard let clientError = error as? MCPClientError else {
            return false
        }
        switch clientError {
        case .requestTimeout, .unexpectedCancellation:
            return true
        default:
            return false
        }
    }

    private static func normalizedCancellation(
        _ error: any Error,
        server: String,
        operation: String
    ) -> any Error {
        guard error is CancellationError, !Task.isCancelled else {
            return error
        }
        return MCPClientError.unexpectedCancellation(
            server: server,
            operation: operation
        )
    }

    private func shouldFinishForcedDisconnection(
        expectedGeneration: UUID
    ) -> Bool {
        switch state {
        case .connected:
            return connectionGeneration == expectedGeneration
        case .transportFailed:
            return true
        case .idle, .connecting, .disconnecting, .cleanupFailed, .disconnected:
            return false
        }
    }
}
