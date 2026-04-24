import Foundation
import Testing
@testable import SwiftAgent
@testable import SwiftAgentPlugins

@Suite("Plugin Permission Runtime")
struct PluginPermissionRuntimeTests {

    @Test("Workspace-write plugin tool is denied in read-only mode")
    func workspaceWritePluginToolIsDeniedInReadOnlyMode() async throws {
        let tool = try makePluginTool(requiredPermission: .workspaceWrite).makeSwiftAgentTool()
        var config = ToolRuntimeConfiguration.empty
        config.use(PermissionMiddleware(configuration: .readOnly))
        config.register(tool)
        let runtime = ToolRuntime(configuration: config)

        await #expect(throws: PermissionDenied.self) {
            _ = try await runtime.execute(toolName: tool.name, argumentsJSON: #"{"message":"hello"}"#)
        }
    }

    @Test("Danger-full-access plugin tool prompts in standard mode and can proceed")
    func dangerFullAccessPluginToolCanProceedAfterApproval() async throws {
        let tool = try makePluginTool(requiredPermission: .dangerFullAccess).makeSwiftAgentTool()
        let permissionConfig = PermissionConfiguration.standard.withHandler(AlwaysAllowHandler())
        var config = ToolRuntimeConfiguration.empty
        config.use(PermissionMiddleware(configuration: permissionConfig))
        config.register(tool)
        let runtime = ToolRuntime(configuration: config)

        let output = try await runtime.execute(toolName: tool.name, argumentsJSON: #"{"message":"hello"}"#)
        let outputObject = try JSONSerialization.jsonObject(with: Data(output.utf8)) as? [String: String]

        #expect(outputObject?["message"] == "hello")
    }

    @Test("Danger-full-access plugin tool is denied in standard mode without a handler")
    func dangerFullAccessPluginToolIsDeniedWithoutApprovalHandler() async throws {
        let tool = try makePluginTool(requiredPermission: .dangerFullAccess).makeSwiftAgentTool()
        var config = ToolRuntimeConfiguration.empty
        config.use(PermissionMiddleware(configuration: .standard))
        config.register(tool)
        let runtime = ToolRuntime(configuration: config)

        await #expect(throws: PermissionDenied.self) {
            _ = try await runtime.execute(toolName: tool.name, argumentsJSON: #"{"message":"hello"}"#)
        }
    }

    private func makePluginTool(requiredPermission: PluginToolPermission) -> PluginTool {
        PluginTool(
            pluginID: "echo-tools@external",
            pluginName: "echo-tools",
            definition: PluginToolDefinition(
                name: "echo_json",
                description: "Echo JSON back",
                inputSchema: .object([
                    "type": .string("object"),
                    "properties": .object([
                        "message": .object([
                            "type": .string("string")
                        ])
                    ])
                ])
            ),
            command: "cat",
            args: [],
            requiredPermission: requiredPermission,
            rootPath: nil
        )
    }
}
