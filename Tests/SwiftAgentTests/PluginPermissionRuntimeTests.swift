import Foundation
import Testing
@testable import SwiftAgent
@testable import SwiftAgentPlugins

@Suite("Plugin Permission Runtime")
struct PluginPermissionRuntimeTests {

    @Test("Workspace-write plugin tool is denied in read-only mode")
    func workspaceWritePluginToolIsDeniedInReadOnlyMode() async throws {
        let tool = try makePluginTool(requiredPermission: .workspaceWrite).makeSwiftAgentTool()
        let pipeline = ToolPipeline.empty.use(PermissionMiddleware(configuration: .readOnly))
        let wrappedTool = pipeline.wrap(tool)

        await #expect(throws: PermissionDenied.self) {
            _ = try await wrappedTool.call(arguments: try GeneratedContent(json: #"{"message":"hello"}"#))
        }
    }

    @Test("Danger-full-access plugin tool prompts in standard mode and can proceed")
    func dangerFullAccessPluginToolCanProceedAfterApproval() async throws {
        let tool = try makePluginTool(requiredPermission: .dangerFullAccess).makeSwiftAgentTool()
        let config = PermissionConfiguration.standard.withHandler(AlwaysAllowHandler())
        let pipeline = ToolPipeline.empty.use(PermissionMiddleware(configuration: config))
        let wrappedTool = pipeline.wrap(tool)

        let output = try await wrappedTool.call(arguments: try GeneratedContent(json: #"{"message":"hello"}"#))
        let outputObject = try JSONSerialization.jsonObject(with: Data(output.utf8)) as? [String: String]

        #expect(outputObject?["message"] == "hello")
    }

    @Test("Danger-full-access plugin tool is denied in standard mode without a handler")
    func dangerFullAccessPluginToolIsDeniedWithoutApprovalHandler() async throws {
        let tool = try makePluginTool(requiredPermission: .dangerFullAccess).makeSwiftAgentTool()
        let pipeline = ToolPipeline.empty.use(PermissionMiddleware(configuration: .standard))
        let wrappedTool = pipeline.wrap(tool)

        await #expect(throws: PermissionDenied.self) {
            _ = try await wrappedTool.call(arguments: try GeneratedContent(json: #"{"message":"hello"}"#))
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
