//
//  MCPClient.swift
//  AgentMCP
//
//  Created by SwiftAgent on 2025/01/31.
//

import Foundation
import System
import SwiftAgent

// MARK: - MCP Server Configuration

/// Transport configuration for MCP server connection
public enum MCPTransportConfig: Sendable {
    /// Stdio transport - communicate with a local subprocess
    case stdio(
        command: String,
        arguments: [String] = [],
        environment: [String: String]? = nil,
        workingDirectory: URL? = nil
    )

    /// HTTP transport - communicate with a remote server
    case http(
        endpoint: URL,
        headers: [String: String] = [:]
    )

    /// SSE (Server-Sent Events) transport - for real-time bidirectional communication
    case sse(
        endpoint: URL,
        headers: [String: String] = [:],
        autoReconnect: Bool = true
    )
}

// MARK: - Timeout Configuration

/// Timeout configuration for MCP operations
public struct MCPTimeoutConfig: Sendable {

    /// Server startup timeout (default: 30 seconds)
    public let startup: Duration

    /// Tool execution timeout (default: 120 seconds)
    public let toolExecution: Duration

    /// Default timeout configuration
    public static let `default` = MCPTimeoutConfig(
        startup: .seconds(30),
        toolExecution: .seconds(120)
    )

    public init(startup: Duration, toolExecution: Duration) {
        self.startup = startup
        self.toolExecution = toolExecution
    }

    /// Load timeout configuration from environment variables
    ///
    /// - `MCP_TIMEOUT`: Server startup timeout in milliseconds
    /// - `MCP_TOOL_TIMEOUT`: Tool execution timeout in milliseconds
    public static func fromEnvironment() -> MCPTimeoutConfig {
        let startup = ProcessInfo.processInfo.environment["MCP_TIMEOUT"]
            .flatMap { Int($0) }
            .map { Duration.milliseconds($0) } ?? .seconds(30)

        let tool = ProcessInfo.processInfo.environment["MCP_TOOL_TIMEOUT"]
            .flatMap { Int($0) }
            .map { Duration.milliseconds($0) } ?? .seconds(120)

        return MCPTimeoutConfig(startup: startup, toolExecution: tool)
    }
}

/// Configuration for an MCP server
public struct MCPServerConfig: Sendable {
    /// Unique name for this server
    public let name: String

    /// Transport configuration
    public let transport: MCPTransportConfig

    /// Authentication configuration (optional)
    public let auth: MCPConfiguration.MCPAuthConfig?

    /// Timeout configuration (optional)
    public let timeout: MCPTimeoutConfig?

    /// Creates a new MCP server configuration
    /// - Parameters:
    ///   - name: Unique name for this server
    ///   - transport: Transport configuration
    ///   - auth: Authentication configuration (optional)
    ///   - timeout: Timeout configuration (optional)
    public init(
        name: String,
        transport: MCPTransportConfig,
        auth: MCPConfiguration.MCPAuthConfig? = nil,
        timeout: MCPTimeoutConfig? = nil
    ) {
        self.name = name
        self.transport = transport
        self.auth = auth
        self.timeout = timeout
    }
}

// MARK: - MCP Client

/// An actor that manages connection to an MCP server and provides tools
public actor MCPClient {
    private let config: MCPServerConfig
    private let client: Client
    private let timeoutConfig: MCPTimeoutConfig
    private var process: Process?
    private var transport: (any Transport)?
    private var isConnected: Bool = false
    private var stderrTask: Task<Void, Never>?

    /// Creates a new MCP client with the given configuration
    /// - Parameter config: The server configuration
    private init(config: MCPServerConfig) {
        self.config = config
        self.client = Client(name: SwiftAgent.Info.name, version: SwiftAgent.Info.version)
        self.timeoutConfig = config.timeout ?? MCPTimeoutConfig.fromEnvironment()
    }

    /// Connects to an MCP server using the provided configuration
    /// - Parameter config: The server configuration
    /// - Returns: A connected MCP client
    public static func connect(config: MCPServerConfig) async throws -> MCPClient {
        let mcpClient = MCPClient(config: config)
        try await mcpClient.establishConnection()
        return mcpClient
    }

    /// Establishes connection to the MCP server with timeout
    private func establishConnection() async throws {
        try await withThrowingTaskGroup(of: Void.self) { group in
            // Connection task
            group.addTask {
                try await self.connectTransport()
            }

            // Timeout task
            group.addTask {
                try await Task.sleep(for: self.timeoutConfig.startup)
                throw MCPClientError.connectionTimeout
            }

            // Wait for first to complete (success or timeout)
            do {
                try await group.next()
                group.cancelAll()
            } catch {
                group.cancelAll()
                throw error
            }
        }
    }

    /// Connects via the configured transport
    private func connectTransport() async throws {
        switch config.transport {
        case .stdio(let command, let arguments, let environment, let workingDirectory):
            try await connectViaStdio(
                command: command,
                arguments: arguments,
                environment: environment,
                workingDirectory: workingDirectory
            )
        case .http(let endpoint, let headers):
            try await connectViaHTTP(endpoint: endpoint, headers: headers)
        case .sse(let endpoint, let headers, _):
            try await connectViaSSE(endpoint: endpoint, headers: headers)
        }
    }

    /// Connects via stdio transport (subprocess)
    private func connectViaStdio(
        command: String,
        arguments: [String],
        environment: [String: String]?,
        workingDirectory: URL?
    ) async throws {
        // Create the subprocess
        let process = Process()
        process.executableURL = URL(fileURLWithPath: command)
        process.arguments = arguments

        if let env = environment {
            var processEnv = ProcessInfo.processInfo.environment
            for (key, value) in env {
                processEnv[key] = value
            }
            process.environment = processEnv
        }

        if let workDir = workingDirectory {
            process.currentDirectoryURL = workDir
        }

        // Set up pipes for stdio communication
        let stdinPipe = Pipe()
        let stdoutPipe = Pipe()
        let stderrPipe = Pipe()

        process.standardInput = stdinPipe
        process.standardOutput = stdoutPipe
        process.standardError = stderrPipe

        // Start the process
        try process.run()
        self.process = process

        // Start task to drain stderr to prevent pipe blocking.
        // The FileHandle is owned by stderrPipe, which is retained by Process.
        // When Process terminates, availableData returns empty and loop exits.
        let stderrHandle = stderrPipe.fileHandleForReading
        stderrTask = Task.detached {
            while true {
                let data = stderrHandle.availableData
                if data.isEmpty { break }
                // Stderr is discarded to prevent pipe buffer from filling up
            }
        }

        // Create FileDescriptors from the pipe file handles
        let inputFD = FileDescriptor(rawValue: stdoutPipe.fileHandleForReading.fileDescriptor)
        let outputFD = FileDescriptor(rawValue: stdinPipe.fileHandleForWriting.fileDescriptor)

        // Create stdio transport with the pipes
        let transport = StdioTransport(
            input: inputFD,
            output: outputFD
        )
        self.transport = transport

        // Connect (initialization happens automatically)
        try await client.connect(transport: transport)
        isConnected = true
    }

    /// Connects via HTTP transport (standard request-response mode)
    ///
    /// - Note: Custom headers are currently not supported by the MCP SDK's HTTPClientTransport.
    ///   This is a known limitation. For OAuth authentication, consider using bearer tokens
    ///   configured through the MCP server's native authentication mechanism.
    private func connectViaHTTP(endpoint: URL, headers: [String: String] = [:]) async throws {
        // TODO: MCP SDK HTTPClientTransport does not currently support custom headers.
        // When the SDK adds support, inject headers here for OAuth/bearer auth.
        // streaming: false = standard HTTP request-response mode
        let transport = HTTPClientTransport(endpoint: endpoint, streaming: false)
        self.transport = transport

        try await client.connect(transport: transport)
        isConnected = true
    }

    /// Connects via SSE (Server-Sent Events) transport
    ///
    /// SSE mode uses HTTPClientTransport with `streaming: true` to enable
    /// Server-Sent Events for real-time server-pushed updates.
    ///
    /// - Note: Custom headers are currently not supported by the MCP SDK's HTTPClientTransport.
    ///   This is a known limitation. For OAuth authentication, consider using bearer tokens
    ///   configured through the MCP server's native authentication mechanism.
    private func connectViaSSE(endpoint: URL, headers: [String: String] = [:]) async throws {
        // TODO: MCP SDK HTTPClientTransport does not currently support custom headers.
        // When the SDK adds support, inject headers here for OAuth/bearer auth.
        // streaming: true = SSE mode for server-pushed events
        let transport = HTTPClientTransport(endpoint: endpoint, streaming: true)
        self.transport = transport

        try await client.connect(transport: transport)
        isConnected = true
    }

    /// Disconnects from the MCP server
    public func disconnect() async {
        isConnected = false

        // Cancel stderr drain task
        stderrTask?.cancel()
        stderrTask = nil

        // Terminate the subprocess if running
        if let process = process, process.isRunning {
            process.terminate()
            process.waitUntilExit()
        }
        process = nil
        transport = nil
    }

    /// Lists all available tools from the MCP server
    /// - Returns: Array of MCP tools
    public func listTools() async throws -> [MCP.Tool] {
        guard isConnected else {
            throw MCPClientError.notConnected
        }
        let (tools, _) = try await client.listTools()
        return tools
    }

    /// Calls a tool on the MCP server with timeout
    /// - Parameters:
    ///   - name: The name of the tool
    ///   - arguments: The arguments to pass
    /// - Returns: The tool result content and error flag
    /// - Throws: `MCPClientError.toolCallTimeout` if the tool execution exceeds the timeout
    public func callTool(name: String, arguments: [String: Value]?) async throws -> ([MCP.Tool.Content], Bool) {
        guard isConnected else {
            throw MCPClientError.notConnected
        }

        // Execute with timeout
        return try await withThrowingTaskGroup(of: ([MCP.Tool.Content], Bool).self) { group in
            // Tool execution task
            group.addTask {
                let result = try await self.client.callTool(name: name, arguments: arguments)
                return (result.content, result.isError ?? false)
            }

            // Timeout task
            group.addTask {
                try await Task.sleep(for: self.timeoutConfig.toolExecution)
                throw MCPClientError.toolCallTimeout(name)
            }

            // Wait for first to complete
            do {
                let result = try await group.next()!
                group.cancelAll()
                return result
            } catch {
                group.cancelAll()
                throw error
            }
        }
    }

    /// Lists all available resources from the MCP server
    /// - Returns: Array of resources
    public func listResources() async throws -> [Resource] {
        guard isConnected else {
            throw MCPClientError.notConnected
        }
        let (resources, _) = try await client.listResources()
        return resources
    }

    /// Reads a resource from the MCP server
    /// - Parameter uri: The resource URI
    /// - Returns: The resource contents
    public func readResource(uri: String) async throws -> [Resource.Content] {
        guard isConnected else {
            throw MCPClientError.notConnected
        }
        return try await client.readResource(uri: uri)
    }

    /// Reads a resource and returns its text content
    /// - Parameter uri: The resource URI
    /// - Returns: The text content of the resource
    public func resourceAsText(uri: String) async throws -> String {
        let contents = try await readResource(uri: uri)
        return contents.compactMap { $0.text }.joined(separator: "\n")
    }

    /// Lists all available prompts from the MCP server
    /// - Returns: Array of prompts
    public func listPrompts() async throws -> [MCP.Prompt] {
        guard isConnected else {
            throw MCPClientError.notConnected
        }
        let (prompts, _) = try await client.listPrompts()
        return prompts
    }

    /// Gets a prompt from the MCP server
    /// - Parameters:
    ///   - name: The prompt name
    ///   - arguments: The arguments to pass
    /// - Returns: The prompt description and messages
    public func getPrompt(name: String, arguments: [String: String]?) async throws -> (String?, [MCP.Prompt.Message]) {
        guard isConnected else {
            throw MCPClientError.notConnected
        }
        // Convert [String: String] to [String: Value]
        let valueArgs: [String: Value]? = arguments?.mapValues { .string($0) }
        return try await client.getPrompt(name: name, arguments: valueArgs)
    }

    /// The server name
    public var name: String {
        config.name
    }
}

// MARK: - MCP Client Errors

/// Errors that can occur with MCP client operations
public enum MCPClientError: Error, LocalizedError {
    case notConnected
    case connectionFailed(String)
    case connectionTimeout
    case toolCallFailed(String, String)
    case toolCallTimeout(String)
    case processLaunchFailed(String)
    case serverNotFound(String)
    case authenticationFailed(String)
    case reconnectionFailed(String)

    public var errorDescription: String? {
        switch self {
        case .notConnected:
            return "MCP client is not connected"
        case .connectionFailed(let message):
            return "MCP connection failed: \(message)"
        case .connectionTimeout:
            return "MCP connection timed out"
        case .toolCallFailed(let name, let message):
            return "MCP tool '\(name)' call failed: \(message)"
        case .toolCallTimeout(let name):
            return "MCP tool '\(name)' call timed out"
        case .processLaunchFailed(let message):
            return "Failed to launch MCP server process: \(message)"
        case .serverNotFound(let name):
            return "MCP server '\(name)' not found"
        case .authenticationFailed(let message):
            return "MCP authentication failed: \(message)"
        case .reconnectionFailed(let message):
            return "MCP reconnection failed: \(message)"
        }
    }
}
