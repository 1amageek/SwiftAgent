import Foundation

public enum MCPClientError: Error, LocalizedError, Sendable {
    case notConnected(server: String)
    case connectionTimeout(server: String)
    case requestTimeout(server: String, operation: String)
    case unexpectedCancellation(server: String, operation: String)
    case requestCancellationAndCleanupFailed(
        server: String,
        cancellation: String,
        cleanup: String
    )
    case transportTerminated(server: String, reason: String)
    case disabledServer(String)
    case serverNotFound(String)
    case duplicateServer(String)
    case processLaunchFailed(server: String, reason: String)
    case processCleanupFailed(server: String, reasons: [String])
    case connectionAndCleanupFailed(server: String, connection: String, cleanup: String)
    case connectionReplacementCleanupFailed(server: String, cleanup: String)
    case serverTransitionInProgress(String)
    case serverCatalogChanged
    case nonTextResource(server: String, uri: String)
    case paginationCycle(server: String, operation: String, cursor: String)
    case paginationLimitExceeded(server: String, operation: String, limit: Int)
    case messageTooLarge(
        server: String,
        direction: String,
        actual: Int,
        maximum: Int
    )
    case multipleDisconnectFailures([String])
    case loadAndCleanupFailed(
        load: String,
        cleanup: String,
        recovery: MCPClientManager
    )

    /// Retains cleanup ownership when configuration loading cannot release all resources.
    public var recoveryManager: MCPClientManager? {
        guard case .loadAndCleanupFailed(_, _, let recovery) = self else {
            return nil
        }
        return recovery
    }

    public var errorDescription: String? {
        switch self {
        case .notConnected(let server):
            return "MCP server '\(server)' is not connected"
        case .connectionTimeout(let server):
            return "MCP server '\(server)' connection timed out"
        case .requestTimeout(let server, let operation):
            return "MCP request '\(server)/\(operation)' timed out"
        case .unexpectedCancellation(let server, let operation):
            return "MCP operation '\(server)/\(operation)' cancelled without caller or lifecycle cancellation"
        case .requestCancellationAndCleanupFailed(
            let server,
            let cancellation,
            let cleanup
        ):
            return "MCP server '\(server)' request cancellation failed (\(cancellation)); process cleanup also failed (\(cleanup))"
        case .transportTerminated(let server, let reason):
            return "MCP server '\(server)' transport terminated: \(reason)"
        case .disabledServer(let server):
            return "MCP server '\(server)' is disabled"
        case .serverNotFound(let server):
            return "MCP server '\(server)' was not found"
        case .duplicateServer(let server):
            return "MCP server '\(server)' is already registered"
        case .processLaunchFailed(let server, let reason):
            return "MCP server '\(server)' process could not be launched: \(reason)"
        case .processCleanupFailed(let server, let reasons):
            return "MCP server '\(server)' process cleanup failed: \(reasons.joined(separator: "; "))"
        case .connectionAndCleanupFailed(let server, let connection, let cleanup):
            return "MCP server '\(server)' connection failed (\(connection)); cleanup also failed (\(cleanup))"
        case .connectionReplacementCleanupFailed(let server, let cleanup):
            return "MCP server '\(server)' was replaced, but the previous connection cleanup failed: \(cleanup)"
        case .serverTransitionInProgress(let server):
            return "MCP server '\(server)' already has a lifecycle transition in progress"
        case .serverCatalogChanged:
            return "The MCP server catalog changed while an aggregate snapshot was being built"
        case .nonTextResource(let server, let uri):
            return "MCP resource '\(server)/\(uri)' contains non-text content"
        case .paginationCycle(let server, let operation, let cursor):
            return "MCP server '\(server)' repeated cursor '\(cursor)' while listing \(operation)"
        case .paginationLimitExceeded(let server, let operation, let limit):
            return "MCP server '\(server)' exceeded the \(limit)-page limit while listing \(operation)"
        case .messageTooLarge(
            let server,
            let direction,
            let actual,
            let maximum
        ):
            return "MCP server '\(server)' \(direction) message is \(actual) bytes, exceeding the \(maximum)-byte limit"
        case .multipleDisconnectFailures(let reasons):
            return "One or more MCP servers failed to disconnect: \(reasons.joined(separator: "; "))"
        case .loadAndCleanupFailed(let load, let cleanup, _):
            return "MCP configuration load failed (\(load)); cleanup also failed (\(cleanup))"
        }
    }
}
