import Foundation

/// Deadlines for connection establishment and individual MCP requests.
public struct MCPTimeoutConfig: Sendable {
    public static let `default` = MCPTimeoutConfig(
        startup: .seconds(30),
        requestExecution: .seconds(30),
        toolExecution: .seconds(120)
    )

    public let startup: Duration
    public let requestExecution: Duration
    public let toolExecution: Duration

    public init(
        startup: Duration,
        requestExecution: Duration,
        toolExecution: Duration
    ) {
        self.startup = startup
        self.requestExecution = requestExecution
        self.toolExecution = toolExecution
    }

    public static func fromEnvironment(
        _ environment: [String: String] = ProcessInfo.processInfo.environment
    ) throws -> MCPTimeoutConfig {
        MCPTimeoutConfig(
            startup: try duration(
                environment["MCP_STARTUP_TIMEOUT"],
                variable: "MCP_STARTUP_TIMEOUT",
                defaultValue: .seconds(30)
            ),
            requestExecution: try duration(
                environment["MCP_REQUEST_TIMEOUT"],
                variable: "MCP_REQUEST_TIMEOUT",
                defaultValue: .seconds(30)
            ),
            toolExecution: try duration(
                environment["MCP_TOOL_TIMEOUT"],
                variable: "MCP_TOOL_TIMEOUT",
                defaultValue: .seconds(120)
            )
        )
    }

    private static func duration(
        _ value: String?,
        variable: String,
        defaultValue: Duration
    ) throws -> Duration {
        guard let value else {
            return defaultValue
        }
        guard let milliseconds = Int64(value), milliseconds > 0 else {
            throw MCPConfigurationError.invalidEnvironmentValue(variable: variable, value: value)
        }
        return .milliseconds(milliseconds)
    }
}
