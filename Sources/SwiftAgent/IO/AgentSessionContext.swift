//
//  AgentSessionContext.swift
//  SwiftAgent
//

/// Identity context provided by `AgentSession` during turn execution.
///
/// Propagated via TaskLocal, making session and turn identifiers available
/// to middleware (e.g., `EventEmittingMiddleware`) without requiring them
/// to be passed explicitly through the call chain.
///
/// ## Usage
///
/// ```swift
/// // Reading (in middleware or tools):
/// if let context = AgentSessionContext.current {
///     print("Session: \(context.sessionID), Turn: \(context.turnID)")
/// }
/// ```
public struct AgentSessionContext: Sendable {

    /// The session ID for the current run.
    public let sessionID: String

    /// The turn ID for the current request.
    public let turnID: String

    public init(sessionID: String, turnID: String) {
        self.sessionID = sessionID
        self.turnID = turnID
    }

    // MARK: - TaskLocal

    @TaskLocal public static var current: AgentSessionContext?
}
