import Foundation
import MCP
import SwiftAgent
import Testing
@testable import SwiftAgentMCP

@Suite("MCP configuration")
struct MCPConfigurationTests {
    @Test("Missing environment variables fail closed")
    func missingEnvironmentVariableFails() throws {
        let configuration = MCPConfiguration(mcpServers: [
            "local": .init(
                command: "/usr/bin/env",
                args: ["${MISSING_COMMAND}"]
            )
        ])

        #expect(throws: MCPConfigurationError.self) {
            _ = try configuration.expandEnvironmentVariables(using: [:])
        }
    }

    @Test("Legacy SSE transport is rejected")
    func legacySSETransportIsRejected() throws {
        let configuration = MCPConfiguration(mcpServers: [
            "remote": .init(
                url: "https://example.com/mcp",
                transport: "sse"
            )
        ])

        #expect(throws: MCPConfigurationError.self) {
            _ = try configuration.serverConfigs()
        }
    }

    @Test("Obsolete aggregate timeout is rejected instead of ignored")
    func obsoleteTimeoutFieldIsRejected() {
        let data = Data(
            #"{"mcpServers":{"local":{"command":"/usr/bin/env","timeout":5000}}}"#.utf8
        )

        #expect(throws: MCPConfigurationError.self) {
            _ = try MCPConfiguration.load(from: data)
        }
    }

    @Test("Unknown configuration fields are rejected")
    func unknownConfigurationFieldIsRejected() {
        let data = Data(
            #"{"mcpServers":{"local":{"command":"/usr/bin/env","requestTimout":5000}}}"#.utf8
        )

        #expect(throws: MCPConfigurationError.self) {
            _ = try MCPConfiguration.load(from: data)
        }
    }

    @Test("Unknown top-level fields are rejected")
    func unknownTopLevelFieldIsRejected() {
        let data = Data(
            #"{"mcpServers":{},"servers":{}}"#.utf8
        )

        #expect(throws: MCPConfigurationError.self) {
            _ = try MCPConfiguration.load(from: data)
        }
    }

    @Test("Each request phase has an independent timeout")
    func explicitTimeoutsAreMappedIndependently() throws {
        let configuration = MCPConfiguration(mcpServers: [
            "local": .init(
                command: "/usr/bin/env",
                startupTimeout: 1_000,
                requestTimeout: 2_000,
                toolTimeout: 3_000
            )
        ])

        let config = try #require(configuration.serverConfigs().first)

        #expect(config.timeout?.startup == .milliseconds(1_000))
        #expect(config.timeout?.requestExecution == .milliseconds(2_000))
        #expect(config.timeout?.toolExecution == .milliseconds(3_000))
    }

    @Test("Message byte limits are explicit and positive")
    func messageByteLimitIsValidated() throws {
        let configuration = MCPConfiguration(mcpServers: [
            "local": .init(
                command: "/usr/bin/env",
                maximumMessageBytes: 1_024
            )
        ])

        let config = try #require(configuration.serverConfigs().first)
        #expect(config.maximumMessageBytes == 1_024)

        #expect(throws: MCPConfigurationError.self) {
            _ = try MCPServerConfig(
                name: "invalid-limit",
                transport: .stdio(command: "/usr/bin/env"),
                maximumMessageBytes: 0
            )
        }
    }

    @Test("Remote plain HTTP is rejected")
    func remotePlainHTTPIsRejected() throws {
        let configuration = MCPConfiguration(mcpServers: [
            "remote": .init(
                url: "http://example.com/mcp",
                transport: "streamable-http"
            )
        ])

        #expect(throws: MCPConfigurationError.self) {
            _ = try configuration.serverConfigs()
        }
    }

    @Test("Authorization header belongs to the authorization boundary")
    func authorizationHeaderIsRejectedFromHeaders() throws {
        let endpoint = try #require(URL(string: "https://example.com/mcp"))
        #expect(throws: MCPConfigurationError.self) {
            _ = try MCPServerConfig(
                name: "remote",
                transport: .streamableHTTP(
                    endpoint: endpoint,
                    headers: ["authorization": "Bearer secret"]
                )
            )
        }
    }

    @Test("Transport-owned HTTP headers are rejected")
    func transportOwnedHeadersAreRejected() throws {
        let endpoint = try #require(URL(string: "https://example.com/mcp"))
        #expect(throws: MCPConfigurationError.self) {
            _ = try MCPServerConfig(
                name: "remote",
                transport: .streamableHTTP(
                    endpoint: endpoint,
                    headers: ["Host": "different.example"]
                )
            )
        }
    }

    @Test("Authorization values cannot inject HTTP headers")
    func authorizationHeaderInjectionIsRejected() throws {
        let endpoint = try #require(URL(string: "https://example.com/mcp"))
        #expect(throws: MCPConfigurationError.self) {
            _ = try MCPServerConfig(
                name: "remote",
                transport: .streamableHTTP(endpoint: endpoint),
                authorization: .bearer(token: "token\r\nX-Injected: value")
            )
        }
    }

    @Test("Authorization fields cannot be silently ignored")
    func conflictingAuthorizationFieldsAreRejected() throws {
        let configuration = MCPConfiguration(mcpServers: [
            "remote": .init(
                url: "https://example.com/mcp",
                transport: "streamable-http",
                auth: MCPAuthConfig(
                    type: "bearer",
                    token: "secret",
                    username: "ignored"
                )
            )
        ])

        #expect(throws: MCPConfigurationError.self) {
            _ = try configuration.serverConfigs()
        }
    }

    @Test("Unknown authorization fields are rejected")
    func unknownAuthorizationFieldIsRejected() {
        let data = Data(
            #"{"mcpServers":{"remote":{"url":"https://example.com/mcp","auth":{"type":"bearer","token":"secret","audience":"ignored"}}}}"#.utf8
        )

        #expect(throws: MCPConfigurationError.self) {
            _ = try MCPConfiguration.load(from: data)
        }
    }

    @Test("OAuth client credentials cannot inject HTTP fields")
    func oauthClientCredentialInjectionIsRejected() throws {
        let configuration = MCPConfiguration(mcpServers: [
            "remote": .init(
                url: "https://example.com/mcp",
                transport: "streamable-http",
                auth: MCPAuthConfig(
                    type: "oauth-client-credentials",
                    clientId: "client",
                    clientSecret: "secret\r\nX-Injected: value"
                )
            )
        ])

        #expect(throws: MCPConfigurationError.self) {
            _ = try configuration.serverConfigs()
        }
    }

    @Test("OAuth scopes are individual protocol tokens")
    func oauthScopesRejectEmbeddedSeparators() throws {
        let configuration = MCPConfiguration(mcpServers: [
            "remote": .init(
                url: "https://example.com/mcp",
                transport: "streamable-http",
                auth: MCPAuthConfig(
                    type: "oauth-client-credentials",
                    scopes: ["read write"],
                    clientId: "client",
                    clientSecret: "secret"
                )
            )
        ])

        #expect(throws: MCPConfigurationError.self) {
            _ = try configuration.serverConfigs()
        }
    }

    @Test("Stdio rejects HTTP authorization")
    func stdioAuthorizationIsRejected() {
        #expect(throws: MCPConfigurationError.self) {
            _ = try MCPServerConfig(
                name: "local",
                transport: .stdio(command: "/usr/bin/env"),
                authorization: .bearer(token: "secret")
            )
        }
    }

    @Test("Server names cannot escape the MCP permission namespace")
    func serverNamespaceInjectionIsRejected() {
        #expect(throws: MCPConfigurationError.self) {
            _ = try MCPServerConfig(
                name: "github:*",
                transport: .stdio(command: "/usr/bin/env")
            )
        }
    }

    @Test("Server names must leave room for a qualified tool name")
    func oversizedServerNamespaceIsRejected() {
        #expect(throws: MCPConfigurationError.self) {
            _ = try MCPServerConfig(
                name: String(repeating: "s", count: 120),
                transport: .stdio(command: "/usr/bin/env")
            )
        }
    }

    @Test("Disabled server configurations remain addressable")
    func disabledConfigurationsAreRetained() throws {
        let configuration = MCPConfiguration(mcpServers: [
            "disabled": .init(
                command: "/usr/bin/env",
                disabled: true
            )
        ])

        #expect(try configuration.serverConfigs().isEmpty)
        let resolved = try configuration.resolvedServerConfigs()
        #expect(resolved.count == 1)
        #expect(resolved.first?.config.name == "disabled")
        #expect(resolved.first?.isEnabled == false)
    }
}

@Suite("MCP tool bridge")
struct MCPToolBridgeTests {
    @Test("Permission rules share the qualified tool namespace")
    func permissionRulesShareQualifiedNamespace() throws {
        let rule = try MCPPermissionRules.allTools(on: "github")
        let githubTool = try MCPToolNamespace.qualifiedName(
            serverName: "github",
            toolName: "search_repos"
        )
        let slackTool = try MCPToolNamespace.qualifiedName(
            serverName: "slack",
            toolName: "search_repos"
        )

        #expect(rule.matches(ToolContext(toolName: githubTool, arguments: "{}")))
        #expect(!rule.matches(ToolContext(toolName: slackTool, arguments: "{}")))
    }

    @Test("Qualified tool names cannot collide across component boundaries")
    func qualifiedToolNamesAreInjective() throws {
        let first = try MCPToolNamespace.qualifiedName(
            serverName: "a",
            toolName: "b__c"
        )
        let second = try MCPToolNamespace.qualifiedName(
            serverName: "a__b",
            toolName: "c"
        )

        #expect(first != second)
    }

    @Test("Qualified tool names stay within the MCP name bound")
    func qualifiedToolNameHasCombinedLimit() {
        let server = String(repeating: "s", count: 120)

        #expect(throws: MCPToolError.self) {
            _ = try MCPToolNamespace.qualifiedName(
                serverName: server,
                toolName: "tool"
            )
        }
    }

    @Test("Integer schema preserves integer arguments")
    func integerSchemaPreservesIntegerValue() throws {
        let schema: MCPValue = .object([
            "type": "object",
            "properties": .object([
                "count": .object(["type": "integer"])
            ]),
            "required": .array(["count"])
        ])
        let content = try GeneratedContent(json: #"{"count":42}"#)

        let converted = try MCPArgumentValueConverter.convertRoot(content, schema: schema)

        #expect(converted["count"] == .int(42))
    }

    @Test("Array schemas require an item schema")
    func arrayRequiresItemSchema() throws {
        let schema: MCPValue = .object([
            "type": "object",
            "properties": .object([
                "values": .object(["type": "array"])
            ])
        ])

        #expect(throws: MCPToolError.self) {
            _ = try MCPInputSchemaConverter.convertRoot(schema, name: "Arguments")
        }
    }

    @Test("Unsupported schema constraints fail instead of being discarded")
    func unsupportedSchemaConstraintFailsExplicitly() {
        let schema: MCPValue = .object([
            "type": "object",
            "properties": .object([
                "query": .object([
                    "type": "string",
                    "minLength": 1,
                ])
            ]),
        ])

        #expect(throws: MCPToolError.self) {
            _ = try MCPInputSchemaConverter.convertRoot(
                schema,
                name: "Arguments"
            )
        }
    }

    @Test("Generated arguments must match MCP schema types")
    func generatedArgumentTypeIsValidated() throws {
        let schema: MCPValue = .object([
            "type": "object",
            "properties": .object([
                "count": .object(["type": "integer"])
            ]),
            "required": .array(["count"]),
        ])
        let content = try GeneratedContent(json: #"{"count":"42"}"#)

        #expect(throws: MCPToolError.self) {
            _ = try MCPArgumentValueConverter.convertRoot(
                content,
                schema: schema
            )
        }
    }

    @Test("Missing required MCP arguments fail locally")
    func missingRequiredArgumentIsRejected() throws {
        let schema: MCPValue = .object([
            "type": "object",
            "properties": .object([
                "count": .object(["type": "integer"])
            ]),
            "required": .array(["count"]),
        ])
        let content = try GeneratedContent(json: #"{}"#)

        #expect(throws: MCPToolError.self) {
            _ = try MCPArgumentValueConverter.convertRoot(
                content,
                schema: schema
            )
        }
    }

    @Test("Non-text tool content is never discarded")
    func imageResultFailsExplicitly() throws {
        let result = MCPToolResult(
            content: [
                .image(data: "AA==", mimeType: "image/png", annotations: nil, _meta: nil)
            ],
            structuredContent: nil,
            isError: false
        )

        #expect(throws: MCPToolError.self) {
            _ = try MCPToolResultRenderer.render(result, toolName: "image")
        }
    }

    @Test("Structured tool content is rendered deterministically")
    func structuredContentIsPreserved() throws {
        let result = MCPToolResult(
            content: [],
            structuredContent: .object(["value": .int(7)]),
            isError: false
        )

        #expect(try MCPToolResultRenderer.render(result, toolName: "structured") == #"{"value":7}"#)
    }
}
