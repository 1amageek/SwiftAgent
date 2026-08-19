import Foundation
import MCP
import SwiftAgent

/// Declares an MCP server over an explicit set of losslessly representable tools.
public protocol MCPServer {
    init()

    var name: String { get }
    var version: String { get }
    var tools: [any MCPServerTool] { get }
    var maximumConcurrentToolInvocations: Int { get }
    var maximumMessageBytes: Int { get }
}

extension MCPServer {
    public var name: String { String(describing: Self.self) }
    public var version: String { SwiftAgent.Info.version }
    public var maximumConcurrentToolInvocations: Int { 128 }
    public var maximumMessageBytes: Int { 4 * 1_024 * 1_024 }

    public func run(transport: any Transport) async throws {
        guard maximumConcurrentToolInvocations > 0 else {
            throw MCPServerError.invalidInvocationCapacity(
                maximumConcurrentToolInvocations
            )
        }
        guard maximumMessageBytes > 0 else {
            throw MCPServerError.invalidMessageLimit(maximumMessageBytes)
        }
        let toolList = tools
        let toolMap = try validatedToolMap(toolList)
        let toolDefinitions = try toolList.map { tool in
            MCPTool(
                name: tool.name,
                description: tool.description,
                inputSchema: try MCPSchemaConverter.convert(tool.parameters)
            )
        }
        let transportLogger = await transport.logger
        let monitoredTransport = MCPServerTransportMonitor(
            transport: transport,
            maximumMessageBytes: maximumMessageBytes,
            logger: transportLogger
        )
        let invocationRegistry = MCPServerInvocationRegistry(
            maximumConcurrentInvocations: maximumConcurrentToolInvocations
        )
        let server = Server(
            name: name,
            version: version,
            capabilities: .init(tools: .init()),
            configuration: .strict
        )
        let lifecycle = MCPServerLifecycle(
            server: server,
            transport: monitoredTransport,
            invocations: invocationRegistry
        )

        _ = await server
            .withMethodHandler(ListTools.self) { _ in
                ListTools.Result(tools: toolDefinitions)
            }
            .withMethodHandler(CallTool.self) { request in
                guard let tool = toolMap[request.name] else {
                    return CallTool.Result(
                        content: [
                            .text(
                                text: "Unknown tool: \(request.name)",
                                annotations: nil,
                                _meta: nil
                            )
                        ],
                        isError: true
                    )
                }
                do {
                    return try await invocationRegistry.call(
                        tool: tool,
                        arguments: request.arguments
                    )
                } catch is CancellationError {
                    throw CancellationError()
                } catch {
                    return CallTool.Result(
                        content: [
                            .text(
                                text: error.localizedDescription,
                                annotations: nil,
                                _meta: nil
                            )
                        ],
                        isError: true
                    )
                }
            }

        do {
            try await server.start(transport: monitoredTransport)
            await withTaskCancellationHandler {
                await server.waitUntilCompleted()
            } onCancel: {
                Task {
                    await lifecycle.shutdown()
                }
            }
            await lifecycle.shutdown()
            try Task.checkCancellation()
            if let failure = await monitoredTransport.failure() {
                throw failure
            }
        } catch {
            await lifecycle.shutdown()
            throw error
        }
    }

    public func run() async throws {
        try await run(transport: StdioTransport())
    }

    public static func main() async throws {
        try await Self().run()
    }

    private func validatedToolMap(
        _ tools: [any MCPServerTool]
    ) throws -> [String: any MCPServerTool] {
        var result: [String: any MCPServerTool] = [:]
        result.reserveCapacity(tools.count)
        for tool in tools {
            guard MCPToolNamespace.isValidComponent(tool.name) else {
                throw MCPServerError.invalidToolName(tool.name)
            }
            guard result.updateValue(tool, forKey: tool.name) == nil else {
                throw MCPServerError.duplicateToolName(tool.name)
            }
        }
        return result
    }

}
