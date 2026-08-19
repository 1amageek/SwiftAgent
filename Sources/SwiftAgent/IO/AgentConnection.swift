//
//  AgentConnection.swift
//  SwiftAgent
//

/// Owns one bidirectional Agent session connection.
///
/// A concrete adapter owns its wire resources for the entire connection
/// lifetime. ``shutdown()`` must be idempotent and must resume or finish every
/// pending waiter before it returns. Cleanup must continue independently of
/// shutdown-caller cancellation, and concurrent callers must observe the same
/// owned cleanup operation.
public protocol AgentConnection: AgentRequestSource, AgentEventWriter {
    func shutdown() async throws
}
