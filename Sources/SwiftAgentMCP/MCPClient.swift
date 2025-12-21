//
//  MCPClient.swift
//  AgentMCP
//
//  Created by SwiftAgent on 2025/01/31.
//

import Foundation
import MCP
import System

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
    case http(endpoint: URL)
}

/// Configuration for an MCP server
public struct MCPServerConfig: Sendable {
    /// Unique name for this server
    public let name: String

    /// Transport configuration
    public let transport: MCPTransportConfig

    /// Creates a new MCP server configuration
    /// - Parameters:
    ///   - name: Unique name for this server
    ///   - transport: Transport configuration
    public init(name: String, transport: MCPTransportConfig) {
        self.name = name
        self.transport = transport
    }
}

// MARK: - MCP Client

/// An actor that manages connection to an MCP server and provides tools
public actor MCPClient {
    private let config: MCPServerConfig
    private let client: Client
    private var process: Process?
    private var transport: (any Transport)?
    private var isConnected: Bool = false

    /// Creates a new MCP client with the given configuration
    /// - Parameter config: The server configuration
    private init(config: MCPServerConfig) {
        self.config = config
        self.client = Client(name: "SwiftAgent", version: "1.0.0")
    }

    /// Connects to an MCP server using the provided configuration
    /// - Parameter config: The server configuration
    /// - Returns: A connected MCP client
    public static func connect(config: MCPServerConfig) async throws -> MCPClient {
        let mcpClient = MCPClient(config: config)
        try await mcpClient.establishConnection()
        return mcpClient
    }

    /// Establishes connection to the MCP server
    private func establishConnection() async throws {
        switch config.transport {
        case .stdio(let command, let arguments, let environment, let workingDirectory):
            try await connectViaStdio(
                command: command,
                arguments: arguments,
                environment: environment,
                workingDirectory: workingDirectory
            )
        case .http(let endpoint):
            try await connectViaHTTP(endpoint: endpoint)
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

    /// Connects via HTTP transport
    private func connectViaHTTP(endpoint: URL) async throws {
        let transport = HTTPClientTransport(endpoint: endpoint)
        self.transport = transport

        try await client.connect(transport: transport)
        isConnected = true
    }

    /// Disconnects from the MCP server
    public func disconnect() async {
        isConnected = false

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

    /// Calls a tool on the MCP server
    /// - Parameters:
    ///   - name: The name of the tool
    ///   - arguments: The arguments to pass
    /// - Returns: The tool result content and error flag
    public func callTool(name: String, arguments: [String: Value]?) async throws -> ([MCP.Tool.Content], Bool) {
        guard isConnected else {
            throw MCPClientError.notConnected
        }
        let result = try await client.callTool(name: name, arguments: arguments)
        return (result.content, result.isError ?? false)
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
    case toolCallFailed(String, String)
    case processLaunchFailed(String)

    public var errorDescription: String? {
        switch self {
        case .notConnected:
            return "MCP client is not connected"
        case .connectionFailed(let message):
            return "MCP connection failed: \(message)"
        case .toolCallFailed(let name, let message):
            return "MCP tool '\(name)' call failed: \(message)"
        case .processLaunchFailed(let message):
            return "Failed to launch MCP server process: \(message)"
        }
    }
}
