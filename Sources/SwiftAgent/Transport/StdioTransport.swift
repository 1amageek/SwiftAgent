//
//  StdioTransport.swift
//  SwiftAgent
//

import Foundation
import Synchronization

/// A CLI transport that uses stdin/stdout for Agent I/O.
///
/// `StdioTransport` wraps `readLine()` / `print()` to implement
/// the `AgentTransport` protocol, enabling the Agent session to
/// drive interactive CLI sessions.
///
/// ## Usage
///
/// ```swift
/// let transport = StdioTransport(prompt: "You: ")
/// let session = AgentSession(transport: transport)
/// try await session.run(myConversation)
/// ```
///
/// ## Event Rendering
///
/// Events are rendered to stdout as follows:
/// - `.tokenDelta`: Printed inline (no newline) for streaming effect
/// - `.runCompleted`: Prints a newline to finish the response
/// - `.approvalRequired`: Displays a CLI prompt for user decision
/// - `.error`: Printed to stderr
/// - Others: Suppressed unless verbose mode is enabled
public final class StdioTransport: AgentTransport, @unchecked Sendable {

    private let prompt: String
    private let verbose: Bool
    private let state: Mutex<TransportState>

    private struct TransportState {
        var inputClosed = false
        var outputClosed = false
    }

    /// Creates a Stdio transport.
    ///
    /// - Parameters:
    ///   - prompt: The prompt to display before reading input. Defaults to `"> "`.
    ///   - verbose: Whether to print all events (for debugging). Defaults to `false`.
    public init(prompt: String = "> ", verbose: Bool = false) {
        self.prompt = prompt
        self.verbose = verbose
        self.state = Mutex(TransportState())
    }

    // MARK: - AgentTransport

    public var supportsBackgroundReceive: Bool { false }

    public func receive() async throws -> RunRequest {
        let isClosed = state.withLock { $0.inputClosed }
        guard !isClosed else {
            throw TransportError.inputClosed
        }

        print(prompt, terminator: "")
        fflush(stdout)

        guard let line = readLine(), !line.isEmpty else {
            state.withLock { $0.inputClosed = true }
            throw TransportError.inputClosed
        }

        // Check for exit commands
        let trimmed = line.trimmingCharacters(in: .whitespaces)
        if trimmed.lowercased() == "exit" || trimmed.lowercased() == "quit" {
            state.withLock { $0.inputClosed = true }
            throw TransportError.inputClosed
        }

        return RunRequest(input: .text(trimmed))
    }

    public func send(_ event: RunEvent) async throws {
        let isClosed = state.withLock { $0.outputClosed }
        guard !isClosed else {
            throw TransportError.outputClosed
        }

        switch event {
        case .tokenDelta(let delta):
            print(delta.delta, terminator: "")
            fflush(stdout)

        case .runCompleted:
            print()
            fflush(stdout)

        case .approvalRequired(let request):
            printApprovalInfo(request)

        case .error(let error):
            FileHandle.standardError.write(Data("[Error] \(error.message)\n".utf8))

        case .warning(let warning):
            if verbose {
                FileHandle.standardError.write(Data("[Warning] \(warning.message)\n".utf8))
            }

        case .toolCall(let call):
            if verbose {
                print("[Tool] \(call.toolName)")
            }

        case .toolResult(let result):
            if verbose {
                let status = result.success ? "OK" : "FAIL"
                print("[Tool Result] \(result.toolName): \(status) (\(result.duration))")
            }

        case .runStarted, .approvalResolved:
            if verbose {
                print("[Event] \(event)")
            }
        }
    }

    public func closeInput() async {
        state.withLock { $0.inputClosed = true }
    }

    public func close() async {
        state.withLock { state in
            state.inputClosed = true
            state.outputClosed = true
        }
    }

    // MARK: - Approval Handling

    /// Prints approval info (verbose only). The actual approval decision
    /// is handled by the `ApprovalHandler` (e.g., `CLIPermissionHandler`),
    /// not by the transport layer.
    private func printApprovalInfo(_ request: RunEvent.ApprovalRequestEvent) {
        if verbose {
            print("[Approval] \(request.toolName): \(request.operationDescription) (risk: \(request.riskLevel))")
            fflush(stdout)
        }
    }
}
