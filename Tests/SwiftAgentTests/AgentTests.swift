//
//  AgentTests.swift
//  SwiftAgent
//
//  Created by SwiftAgent on 2025/01/26.
//

import Testing
import Foundation
import Synchronization
@testable import SwiftAgent

#if OpenFoundationModels
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
        var instructions: Instructions {
            Instructions("Echo everything back")
        }

        var body: some Step<String, String> {
            Transform { (input: String) in
                "Echo: \(input)"
            }
        }
    }

    @Test("Agent processes text input and returns RunResult", .timeLimit(.minutes(1)))
    func agentProcessesTextInput() async throws {
        let agent = EchoAgent()
        let request = RunRequest(input: .text("Hello"))

        let result = try await agent.run(request)

        #expect(result.status == .completed)
        #expect(result.finalOutput == "Echo: Hello")
    }

    @Test("Agent returns failed for non-text input")
    func agentReturnsFailedForNonTextInput() async throws {
        let agent = EchoAgent()
        let request = RunRequest(input: .cancel)

        let result = try await agent.run(request)

        #expect(result.status == .failed)
        #expect(result.finalOutput == nil)
    }

    @Test("Agent applies steering from context")
    func agentAppliesSteering() async throws {
        let agent = EchoAgent()
        let request = RunRequest(
            input: .text("Hello"),
            context: ContextPayload(steering: ["Be formal", "Be concise"])
        )

        let result = try await agent.run(request)

        #expect(result.status == .completed)
        #expect(result.finalOutput == "Echo: Hello\n\nBe formal\n\nBe concise")
    }
}

// MARK: - Agent with Tools Tests

@Suite("Agent with Tools Tests")
struct AgentWithToolsTests {

    struct ToolAgent: Agent {
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

        var body: some Step<String, String> {
            Transform { (input: String) in
                input
            }
        }
    }

    @Test("Agent tools are accessible")
    func agentToolsAccessible() async throws {
        let agent = ToolAgent(customTools: [])
        #expect(agent.tools.isEmpty)
    }

    @Test("Agent default tools is empty")
    func agentDefaultToolsEmpty() async throws {
        struct NoToolsAgent: Agent {
            var instructions: Instructions {
                Instructions("No tools")
            }

            var body: some Step<String, String> {
                Transform { (input: String) in
                    input
                }
            }
        }

        let agent = NoToolsAgent()
        #expect(agent.tools.isEmpty)
    }
}

// MARK: - Agent Steering Tests

@Suite("Agent Steering Tests")
struct AgentSteeringTests {

    struct SteeringAgent: Agent {
        var instructions: Instructions {
            Instructions("Test steering")
        }

        var body: some Step<String, String> {
            Transform { (input: String) in
                input
            }
        }
    }

    @Test("Agent steering messages are included in run result", .timeLimit(.minutes(1)))
    func agentSteeringIncluded() async throws {
        let agent = SteeringAgent()
        let request = RunRequest(
            input: .text("Hello"),
            context: ContextPayload(steering: ["Use formal tone", "Be concise"])
        )

        let result = try await agent.run(request)

        #expect(result.status == .completed)
        #expect(result.finalOutput?.contains("Hello") == true)
        #expect(result.finalOutput?.contains("Use formal tone") == true)
        #expect(result.finalOutput?.contains("Be concise") == true)
    }
}

// MARK: - AgentSession Send with TokenDelta Tests

@Suite("AgentSession Token Delta Tests")
struct AgentSessionTokenDeltaTests {

    @Test("AgentSession send with onTokenDelta callback", .timeLimit(.minutes(1)))
    func sendWithTokenDelta() async throws {
        let session = AgentSession(languageModelSession: LanguageModelSession(model: MockLanguageModel()) {
            Instructions("Test")
        })

        let receivedDelta = Mutex<String?>(nil)
        let response = try await session.send("Hello") { delta, accumulated in
            receivedDelta.withLock { $0 = delta }
        }

        #expect(response.content == "Mock response")
        #expect(receivedDelta.withLock({ $0 }) == "Mock response")
    }
}

#endif
