//
//  AgentResponse.swift
//  SwiftAgent
//
//  Created by SwiftAgent on 2025/01/15.
//

import Foundation

/// A response from an agent.
///
/// `AgentResponse` contains the generated content along with metadata about
/// the generation process, including tool calls and timing information.
///
/// ## Usage
///
/// ```swift
/// let response = try await session.prompt("Hello!")
/// print(response.content)
///
/// // Check tool calls
/// for toolCall in response.toolCalls {
///     print("Called \(toolCall.toolName)")
/// }
/// ```
public struct AgentResponse<Content: Generable & Sendable>: Sendable {

    /// The generated content.
    public let content: Content

    /// The raw generated content.
    public let rawContent: GeneratedContent

    /// Transcript entries from this response.
    public let transcriptEntries: [Transcript.Entry]

    /// Tool calls made during generation.
    public let toolCalls: [ToolCallRecord]

    /// Time taken for the response.
    public let duration: Duration

    /// Creates an agent response.
    public init(
        content: Content,
        rawContent: GeneratedContent,
        transcriptEntries: [Transcript.Entry],
        toolCalls: [ToolCallRecord],
        duration: Duration
    ) {
        self.content = content
        self.rawContent = rawContent
        self.transcriptEntries = transcriptEntries
        self.toolCalls = toolCalls
        self.duration = duration
    }
}

// MARK: - Convenience Properties

extension AgentResponse {

    /// Whether any tools were called during generation.
    public var hasToolCalls: Bool {
        !toolCalls.isEmpty
    }

    /// The number of tool calls made.
    public var toolCallCount: Int {
        toolCalls.count
    }

    /// Total time spent in tool execution.
    public var toolExecutionTime: Duration {
        toolCalls.reduce(.zero) { $0 + $1.duration }
    }

    /// Names of all tools that were called.
    public var calledToolNames: [String] {
        toolCalls.map { $0.toolName }
    }

    /// Unique names of tools that were called.
    public var uniqueCalledToolNames: Set<String> {
        Set(calledToolNames)
    }
}

// MARK: - String Response Convenience

extension AgentResponse where Content == String {

    /// The content as a trimmed string.
    public var trimmedContent: String {
        content.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// Whether the content is empty.
    public var isEmpty: Bool {
        trimmedContent.isEmpty
    }
}

// MARK: - Tool Call Record

/// A record of a tool call made during agent execution.
public struct ToolCallRecord: Sendable, Identifiable {

    /// Unique identifier for this tool call.
    public let id: String

    /// The name of the tool that was called.
    public let toolName: String

    /// The arguments passed to the tool.
    public let arguments: GeneratedContent

    /// The output from the tool.
    public let output: String

    /// Whether the tool call succeeded.
    public let success: Bool

    /// Error message if the tool call failed.
    public let error: String?

    /// Time taken for the tool call.
    public let duration: Duration

    /// Creates a tool call record.
    public init(
        id: String = UUID().uuidString,
        toolName: String,
        arguments: GeneratedContent,
        output: String,
        success: Bool = true,
        error: String? = nil,
        duration: Duration
    ) {
        self.id = id
        self.toolName = toolName
        self.arguments = arguments
        self.output = output
        self.success = success
        self.error = error
        self.duration = duration
    }
}

// MARK: - Tool Call Record CustomStringConvertible

extension ToolCallRecord: CustomStringConvertible {

    public var description: String {
        let status = success ? "✓" : "✗"
        return "[\(status)] \(toolName) (\(duration))"
    }
}

// MARK: - Agent Response Stream

/// A stream of agent response snapshots.
///
/// `AgentResponseStream` provides real-time access to partial responses
/// as they are generated, including intermediate tool calls.
///
/// ## Usage
///
/// ```swift
/// let stream = session.stream("Write a function...")
///
/// for try await snapshot in stream {
///     print(snapshot.content, terminator: "")
/// }
///
/// let finalResponse = try await stream.collect()
/// ```
public struct AgentResponseStream<Content: Generable & Sendable>: AsyncSequence, Sendable {

    /// A snapshot of the response at a point in time.
    ///
    /// - Note: Uses `@unchecked Sendable` because `Content.PartiallyGenerated`
    ///   may not conform to `Sendable` in the protocol definition, but in practice
    ///   streaming responses are consumed on the same task.
    public struct Snapshot: @unchecked Sendable {

        /// The partial content generated so far.
        public var content: Content.PartiallyGenerated

        /// The raw generated content.
        public var rawContent: GeneratedContent

        /// Tool calls made so far.
        public var toolCalls: [ToolCallRecord]

        /// Whether generation is complete.
        public var isComplete: Bool

        /// Creates a snapshot.
        public init(
            content: Content.PartiallyGenerated,
            rawContent: GeneratedContent,
            toolCalls: [ToolCallRecord] = [],
            isComplete: Bool = false
        ) {
            self.content = content
            self.rawContent = rawContent
            self.toolCalls = toolCalls
            self.isComplete = isComplete
        }
    }

    public typealias Element = Snapshot

    /// The underlying async stream.
    private let stream: AsyncThrowingStream<Snapshot, Error>

    /// Continuation for the stream.
    private let continuation: AsyncThrowingStream<Snapshot, Error>.Continuation?

    /// The start time for duration calculation.
    private let startTime: ContinuousClock.Instant

    /// Creates an agent response stream.
    public init(stream: AsyncThrowingStream<Snapshot, Error>) {
        self.stream = stream
        self.continuation = nil
        self.startTime = ContinuousClock.now
    }

    /// Creates an agent response stream with a continuation.
    internal init(
        stream: AsyncThrowingStream<Snapshot, Error>,
        continuation: AsyncThrowingStream<Snapshot, Error>.Continuation
    ) {
        self.stream = stream
        self.continuation = continuation
        self.startTime = ContinuousClock.now
    }

    // MARK: - AsyncSequence

    public struct AsyncIterator: AsyncIteratorProtocol {
        private var iterator: AsyncThrowingStream<Snapshot, Error>.AsyncIterator

        init(stream: AsyncThrowingStream<Snapshot, Error>) {
            self.iterator = stream.makeAsyncIterator()
        }

        public mutating func next() async throws -> Snapshot? {
            try await iterator.next()
        }
    }

    public func makeAsyncIterator() -> AsyncIterator {
        AsyncIterator(stream: stream)
    }

    // MARK: - Collect

    /// Collects all snapshots and returns the final response.
    ///
    /// This method iterates through all stream snapshots and returns the final
    /// complete response. If the stream produces no snapshots (empty response),
    /// this method throws `AgentError.generationFailed`.
    ///
    /// - Returns: The complete agent response with content, tool calls, and duration.
    /// - Throws: `AgentError.generationFailed` if the stream completes without
    ///   producing any snapshots. This is intentional - an empty response is
    ///   considered an error condition.
    public func collect() async throws -> AgentResponse<Content> {
        var finalSnapshot: Snapshot?
        var allToolCalls: [ToolCallRecord] = []

        for try await snapshot in self {
            finalSnapshot = snapshot
            allToolCalls = snapshot.toolCalls
        }

        guard let snapshot = finalSnapshot else {
            throw AgentError.generationFailed(reason: "Stream completed without content")
        }

        let content = try Content(snapshot.rawContent)
        let duration = ContinuousClock.now - startTime

        return AgentResponse(
            content: content,
            rawContent: snapshot.rawContent,
            transcriptEntries: [],
            toolCalls: allToolCalls,
            duration: duration
        )
    }
}

// MARK: - Agent Response Stream Factory

extension AgentResponseStream {

    /// Creates a stream from a closure that yields snapshots.
    public static func create(
        _ builder: @escaping @Sendable (AsyncThrowingStream<Snapshot, Error>.Continuation) async -> Void
    ) -> AgentResponseStream {
        let stream = AsyncThrowingStream<Snapshot, Error> { continuation in
            Task {
                await builder(continuation)
            }
        }
        return AgentResponseStream(stream: stream)
    }
}

// MARK: - String Response Stream Convenience

extension AgentResponseStream where Content == String {

    /// Collects the stream as a single string.
    public func collectString() async throws -> String {
        let response = try await collect()
        return response.content
    }
}
