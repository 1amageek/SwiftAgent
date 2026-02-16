//
//  AgentTransport.swift
//  SwiftAgent
//

import Foundation

/// A bidirectional transport for Agent I/O.
///
/// Transport adapters handle framing, serialization, and wire-level concerns.
/// The Agent Core operates on `RunRequest` / `RunEvent` / `RunResult` only.
///
/// ## Lifecycle
///
/// ```
/// Transport                    Agent Core
///    │                            │
///    │── receive() ──────────────>│
///    │                            │── process ──>
///    │<──────────── send(event) ──│
///    │<──────────── send(event) ──│
///    │                            │
///    │── receive() ──────────────>│  (next turn)
///    │                            │
///    │── close() ────────────────>│
/// ```
///
/// ## Half-Close
///
/// The transport supports half-close semantics: after `closeInput()`,
/// the transport can still send events. This is needed for HTTP requests
/// where the client sends a single request and receives a stream of SSE events.
///
/// ## Implementations
///
/// - `StdioTransport`: CLI (readLine/print)
/// - `HTTPSSETransport`: HTTP + Server-Sent Events
/// - `WebSocketTransport`: Full-duplex WebSocket
public protocol AgentTransport: Sendable {

    /// Whether the transport can receive messages while a turn is executing.
    ///
    /// Transports that share an I/O channel with approval handlers (e.g., `StdioTransport`
    /// shares stdin with `CLIPermissionHandler`) should return `false` to prevent
    /// the receive loop from competing for the same input stream during turn execution.
    ///
    /// Defaults to `true` for transports with independent receive channels (WebSocket, HTTP).
    var supportsBackgroundReceive: Bool { get }

    /// Receives the next request from the client.
    ///
    /// Blocks until a request is available or the input side is closed.
    ///
    /// - Returns: The next request.
    /// - Throws: `TransportError.inputClosed` when no more requests are available.
    func receive() async throws -> RunRequest

    /// Sends an event to the client.
    ///
    /// - Parameter event: The event to send.
    /// - Throws: `TransportError.outputClosed` if the client has disconnected.
    func send(_ event: RunEvent) async throws

    /// Closes the input side (no more requests will be received).
    ///
    /// Output remains open for in-flight event delivery.
    func closeInput() async

    /// Closes both input and output.
    func close() async
}

extension AgentTransport {
    public var supportsBackgroundReceive: Bool { true }
}

// MARK: - TransportError

/// Errors from the transport layer.
public enum TransportError: Error, Sendable {
    /// The input side of the transport is closed (EOF or connection close).
    case inputClosed

    /// The output side of the transport is closed (client disconnected).
    case outputClosed

    /// Serialization or framing error.
    case encodingError(String)

    /// Deserialization or parsing error.
    case decodingError(String)
}
