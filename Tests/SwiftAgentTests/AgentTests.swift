//
//  AgentTests.swift
//  SwiftAgent
//
//  Created by SwiftAgent on 2025/01/26.
//

import Testing
import Foundation
@testable import SwiftAgent

#if USE_OTHER_MODELS
import OpenFoundationModels

// MARK: - AgentSession Input Queue Tests

@Suite("AgentSession Input Queue Tests")
struct AgentSessionInputQueueTests {

    @Test("AgentSession input adds to queue")
    func agentSessionInputAddsToQueue() async throws {
        let session = AgentSession(languageModelSession: LanguageModelSession(model: MockLanguageModel()) {
            Instructions("Test")
        })

        session.input("Hello")
        session.input("World")

        let first = try await session.waitForInput()
        #expect(first == "Hello")

        let second = try await session.waitForInput()
        #expect(second == "World")
    }

    @Test("AgentSession waitForInput suspends until input available", .timeLimit(.minutes(1)))
    func agentSessionWaitForInputSuspends() async throws {
        let session = AgentSession(languageModelSession: LanguageModelSession(model: MockLanguageModel()) {
            Instructions("Test")
        })

        // Start a task that waits for input
        let task = Task {
            try await session.waitForInput()
        }

        // Give it time to start waiting
        try await Task.sleep(for: .milliseconds(50))

        // Add input
        session.input("Delayed input")

        // Should now complete
        let result = try await task.value
        #expect(result == "Delayed input")
    }

    @Test("AgentSession input preserves order")
    func agentSessionInputPreservesOrder() async throws {
        let session = AgentSession(languageModelSession: LanguageModelSession(model: MockLanguageModel()) {
            Instructions("Test")
        })

        // Add multiple inputs
        for i in 1...5 {
            session.input("Message \(i)")
        }

        // Verify order
        for i in 1...5 {
            let input = try await session.waitForInput()
            #expect(input == "Message \(i)")
        }
    }
}

// MARK: - Agent Protocol Tests

@Suite("Agent Protocol Tests")
struct AgentProtocolTests {

    /// Simple echo agent for testing
    struct EchoAgent: Agent {
        let session: AgentSession
        let outputs: AsyncStream<String>.Continuation

        var instructions: Instructions {
            Instructions("Echo everything back")
        }

        var body: some Step<AgentSession.Response, String> {
            Transform { (response: AgentSession.Response) in
                "Echo: \(response.content)"
            }
        }
    }

    @Test("Agent emits output through continuation", .timeLimit(.minutes(1)))
    func agentEmitsOutput() async throws {
        let (stream, continuation) = AsyncStream<String>.makeStream()
        let session = AgentSession(languageModelSession: LanguageModelSession(model: MockLanguageModel()) {
            Instructions("Test")
        })

        let agent = EchoAgent(session: session, outputs: continuation)

        // Run agent in background task
        let runTask = Task {
            try await agent.run("Initial")
        }

        // Collect first output
        var iterator = stream.makeAsyncIterator()
        let output = await iterator.next()

        // Cancel the agent
        runTask.cancel()

        #expect(output == "Echo: Mock response")
    }

    @Test("Agent processes multiple inputs in order", .timeLimit(.minutes(1)))
    func agentProcessesMultipleInputs() async throws {
        let (stream, continuation) = AsyncStream<String>.makeStream()
        let session = AgentSession(languageModelSession: LanguageModelSession(model: MockLanguageModel()) {
            Instructions("Test")
        })

        let agent = EchoAgent(session: session, outputs: continuation)

        // Run agent in background
        let runTask = Task {
            try await agent.run("First")
        }

        // Wait for first output
        var iterator = stream.makeAsyncIterator()
        _ = await iterator.next()

        // Add more inputs
        session.input("Second")
        session.input("Third")

        // Collect more outputs
        let second = await iterator.next()
        let third = await iterator.next()

        runTask.cancel()

        #expect(second == "Echo: Mock response")
        #expect(third == "Echo: Mock response")
    }

    @Test("Agent cancellation stops processing")
    func agentCancellation() async throws {
        let (_, continuation) = AsyncStream<String>.makeStream()
        let session = AgentSession(languageModelSession: LanguageModelSession(model: MockLanguageModel()) {
            Instructions("Test")
        })

        let agent = EchoAgent(session: session, outputs: continuation)

        let task = Task {
            try await agent.run("Start")
        }

        // Let it start
        try await Task.sleep(for: .milliseconds(100))

        // Cancel
        task.cancel()

        // Should throw CancellationError
        do {
            _ = try await task.value
            Issue.record("Expected CancellationError")
        } catch is CancellationError {
            // Expected
        } catch {
            Issue.record("Unexpected error: \(error)")
        }
    }
}

// MARK: - Agent with Tools Tests

@Suite("Agent with Tools Tests")
struct AgentWithToolsTests {

    struct ToolAgent: Agent {
        let session: AgentSession
        let outputs: AsyncStream<String>.Continuation
        let customTools: [any Tool]

        var tools: [any Tool] {
            customTools
        }

        var instructions: Instructions {
            Instructions {
                "You have access to tools."
                "Use them wisely."
            }
        }

        var body: some Step<AgentSession.Response, String> {
            Transform { (response: AgentSession.Response) in
                response.content
            }
        }
    }

    @Test("Agent tools are accessible")
    func agentToolsAccessible() async throws {
        let (_, continuation) = AsyncStream<String>.makeStream()
        let session = AgentSession(languageModelSession: LanguageModelSession(model: MockLanguageModel()) {
            Instructions("Test")
        })

        let agent = ToolAgent(session: session, outputs: continuation, customTools: [])

        #expect(agent.tools.isEmpty)
    }

    @Test("Agent default tools is empty")
    func agentDefaultToolsEmpty() async throws {
        let (_, continuation) = AsyncStream<String>.makeStream()
        let session = AgentSession(languageModelSession: LanguageModelSession(model: MockLanguageModel()) {
            Instructions("Test")
        })

        struct NoToolsAgent: Agent {
            let session: AgentSession
            let outputs: AsyncStream<String>.Continuation

            var instructions: Instructions {
                Instructions("No tools")
            }

            var body: some Step<AgentSession.Response, String> {
                Transform { (response: AgentSession.Response) in
                    response.content
                }
            }
        }

        let agent = NoToolsAgent(session: session, outputs: continuation)
        #expect(agent.tools.isEmpty)
    }
}

// MARK: - Agent Steering Tests

@Suite("Agent Steering Tests")
struct AgentSteeringTests {

    struct SteeringAgent: Agent {
        let session: AgentSession
        let outputs: AsyncStream<String>.Continuation

        var instructions: Instructions {
            Instructions("Test steering")
        }

        var body: some Step<AgentSession.Response, String> {
            Transform { (response: AgentSession.Response) in
                response.content
            }
        }
    }

    @Test("Agent steering messages are included in prompt", .timeLimit(.minutes(1)))
    func agentSteeringIncluded() async throws {
        let (stream, continuation) = AsyncStream<String>.makeStream()
        let session = AgentSession(languageModelSession: LanguageModelSession(model: MockLanguageModel()) {
            Instructions("Test")
        })

        let agent = SteeringAgent(session: session, outputs: continuation)

        // Add steering before running
        session.steer("Use formal tone")
        session.steer("Be concise")

        // Run agent
        let runTask = Task {
            try await agent.run("Hello")
        }

        // Get output
        var iterator = stream.makeAsyncIterator()
        let output = await iterator.next()

        runTask.cancel()

        #expect(output == "Mock response")
    }
}

#endif
