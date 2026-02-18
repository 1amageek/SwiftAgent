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
            GenerateText { (input: String) in Prompt(input) }
        }

        session.input("Hello")
        session.input("World")

        let first = try await session.waitForInput()
        #expect(first == "Hello")

        let second = try await session.waitForInput()
        #expect(second == "World")
    }

    @Test("Conversation waitForInput suspends until input available", .timeLimit(.minutes(1)))
    func conversationWaitForInputSuspends() async throws {
        let session = Conversation(languageModelSession: LanguageModelSession(model: MockLanguageModel()) {
            Instructions("Test")
        }) {
            GenerateText { (input: String) in Prompt(input) }
        }

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

    @Test("Conversation input preserves order")
    func conversationInputPreservesOrder() async throws {
        let session = Conversation(languageModelSession: LanguageModelSession(model: MockLanguageModel()) {
            Instructions("Test")
        }) {
            GenerateText { (input: String) in Prompt(input) }
        }

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

    @Test("Agent body processes text input")
    func agentBodyProcessesTextInput() async throws {
        let agent = EchoAgent()
        let result = try await agent.body.run("Hello")

        #expect(result == "Echo: Hello")
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

// MARK: - Conversation Steering Tests

@Suite("Conversation Steering Tests")
struct ConversationSteeringTests {

    @Test("Conversation steering messages are included in send", .timeLimit(.minutes(1)))
    func conversationSteeringIncluded() async throws {
        let session = Conversation(languageModelSession: LanguageModelSession(model: MockLanguageModel()) {
            Instructions("Test steering")
        }) {
            Transform { (input: String) in
                input
            }
        }

        session.steer("Be formal")
        session.steer("Be concise")

        let response = try await session.send("Hello")

        #expect(response.content.contains("Hello"))
        #expect(response.content.contains("Be formal"))
        #expect(response.content.contains("Be concise"))
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
            GenerateText(prompt: { (input: String) in Prompt(input) }, onStream: { snapshot in
                receivedContent.withLock { $0 = snapshot.content }
            })
        }

        let response = try await session.send("Hello")

        #expect(response.content == "Mock response")
        #expect(receivedContent.withLock({ $0 }) == "Mock response")
    }
}

#endif
