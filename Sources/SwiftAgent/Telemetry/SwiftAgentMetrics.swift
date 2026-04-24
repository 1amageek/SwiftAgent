//
//  SwiftAgentMetrics.swift
//  SwiftAgent
//

/// Stable metric labels emitted by SwiftAgent.
///
/// Metrics intentionally avoid high-cardinality dimensions such as
/// `sessionID`, `turnID`, `toolUseID`, raw prompts, or arbitrary tool names.
/// Use `RunEvent` for per-run facts and metrics for low-cardinality aggregate
/// observability.
public enum SwiftAgentMetrics {
    /// Count of tool executions that reached the runtime middleware chain.
    public static let toolExecutionsStarted = "swiftagent.tool.executions.started"

    /// Count of tool executions that completed successfully.
    public static let toolExecutionsCompleted = "swiftagent.tool.executions.completed"

    /// Count of tool executions that failed or produced a failed `ToolResult`.
    public static let toolExecutionsFailed = "swiftagent.tool.executions.failed"

    /// Number of tool executions currently active.
    public static let toolExecutionsActive = "swiftagent.tool.executions.active"

    /// Duration of tool executions.
    public static let toolExecutionDuration = "swiftagent.tool.execution.duration"
}
