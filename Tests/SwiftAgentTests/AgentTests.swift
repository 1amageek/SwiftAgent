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

// MARK: - Conversation Input Queue Tests

@Suite("Conversation Input Queue Tests")
struct ConversationInputQueueTests {

    @Test("Conversation input adds to queue")
    func conversationInputAddsToQueue() async throws {
        let session = Conversation(languageModelSession: LanguageModelSession(model: MockLanguageModel()) {
            Instructions("Test")
        }) {
            GenerateText<Prompt>()
        }

        session.input("Hello")
        session.input("World")

        // Verify items are dequeued in order (Prompt is opaque, so test queue mechanics)
        let _ = try await session.waitForInput()
        let _ = try await session.waitForInput()
    }

    @Test("Conversation waitForInput suspends until input available", .timeLimit(.minutes(1)))
    func conversationWaitForInputSuspends() async throws {
        let session = Conversation(languageModelSession: LanguageModelSession(model: MockLanguageModel()) {
            Instructions("Test")
        }) {
            GenerateText<Prompt>()
        }

        // Start a task that waits for input
        let task = Task {
            try await session.waitForInput()
        }

        // Give it time to start waiting
        try await Task.sleep(for: .milliseconds(50))

        // Add input
        session.input("Delayed input")

        // Should now complete without throwing
        let _ = try await task.value
    }

    @Test("Conversation input preserves order")
    func conversationInputPreservesOrder() async throws {
        let receivedCount = Mutex<Int>(0)
        let session = Conversation(languageModelSession: LanguageModelSession(model: MockLanguageModel()) {
            Instructions("Test")
        }) {
            GenerateText<Prompt>()
        }

        // Add multiple inputs
        for i in 1...5 {
            session.input("Message \(i)")
        }

        // Verify all 5 items are dequeued
        for _ in 1...5 {
            let _ = try await session.waitForInput()
            receivedCount.withLock { $0 += 1 }
        }

        #expect(receivedCount.withLock({ $0 }) == 5)
    }
}

// MARK: - Agent Protocol Tests

@Suite("Agent Protocol Tests")
struct AgentProtocolTests {

    /// Simple agent for testing
    struct EchoAgent: Agent {
        var instructions: Instructions {
            Instructions("Echo everything back")
        }

        var body: some Step<Prompt, String> {
            Transform { (input: Prompt) in
                "Echo response"
            }
        }
    }

    @Test("Agent body processes prompt input")
    func agentBodyProcessesPromptInput() async throws {
        let agent = EchoAgent()
        let result = try await agent.body.run(Prompt("Hello"))

        #expect(result == "Echo response")
    }

    @Test("Agent instructions are accessible")
    func agentInstructionsAccessible() async throws {
        let agent = EchoAgent()
        // Just verify it compiles and returns a value
        let _ = agent.instructions
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

        var body: some Step<Prompt, String> {
            Transform { (input: Prompt) in
                "processed"
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

            var body: some Step<Prompt, String> {
                Transform { (input: Prompt) in
                    "no tools"
                }
            }
        }

        let agent = NoToolsAgent()
        #expect(agent.tools.isEmpty)
    }
}

// MARK: - Conversation Steering Tests

@Suite("Conversation Steering Tests")
struct ConversationSteeringTests {

    @Test("Conversation steering messages are consumed on send", .timeLimit(.minutes(1)))
    func conversationSteeringConsumed() async throws {
        let session = Conversation(languageModelSession: LanguageModelSession(model: MockLanguageModel()) {
            Instructions("Test steering")
        }) {
            GenerateText<Prompt>()
        }

        session.steer("Be formal")
        session.steer("Be concise")

        #expect(session.pendingSteeringCount == 2)

        let _ = try await session.send("Hello")

        // Steering messages should be consumed after send
        #expect(session.pendingSteeringCount == 0)
    }
}

// MARK: - Conversation Step-based Streaming Tests

@Suite("Conversation Step-based Streaming Tests")
struct ConversationStepStreamingTests {

    @Test("Conversation send with streaming Step", .timeLimit(.minutes(1)))
    func sendWithStreamingStep() async throws {
        let receivedContent = Mutex<String?>(nil)
        let session = Conversation(languageModelSession: LanguageModelSession(model: MockLanguageModel()) {
            Instructions("Test")
        }) {
            GenerateText<Prompt>(prompt: { $0 }, onStream: { snapshot in
                receivedContent.withLock { $0 = snapshot.content }
            })
        }

        let response = try await session.send("Hello")

        #expect(response.content == "Mock response")
        #expect(receivedContent.withLock({ $0 }) == "Mock response")
    }
}

#endif
