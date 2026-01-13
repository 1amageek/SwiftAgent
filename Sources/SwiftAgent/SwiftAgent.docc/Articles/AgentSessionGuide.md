# Building an Agent Loop

Learn how to build a production-ready agent loop with AgentSession.

## Overview

``AgentSession`` is a thread-safe class for managing interactive conversations with language models. This guide shows how to build a complete agent application step by step.

## Basic Agent Loop

The simplest agent loop:

```swift
import SwiftAgent

// Create session
let session = AgentSession(tools: []) {
    Instructions("You are a helpful assistant.")
}

// Agent loop
while true {
    print("You> ", terminator: "")
    guard let input = readLine(), !input.isEmpty else { continue }
    if input == "exit" { break }

    let response = try await session.send(input)
    print("Agent> \(response.content)")
}
```

## Adding Tools

Tools give the agent capabilities to interact with the environment:

```swift
import AgentTools

let provider = AgentToolsProvider(workingDirectory: "/path/to/work")
let tools = provider.allTools()  // Read, Write, Edit, Glob, Grep, Bash, Git...

let session = AgentSession(tools: tools) {
    Instructions("""
        You are a coding assistant.
        Available tools: read, write, edit, glob, grep, bash, git
        """)
}
```

## Response Structure

``AgentSession/Response`` contains:

```swift
let response = try await session.send("Explain this code")

// Generated text
print(response.content)

// All transcript entries (prompt, tool calls, response)
for entry in response.entries {
    print(entry)
}

// Processing time
print("Took: \(response.duration)")
```

## Steering

Add context to influence the next response without a separate message:

```swift
// Add hints before sending
session.steer("Focus on performance")
session.steer("Use Swift concurrency")

// Steering is consumed by next send()
let response = try await session.send("Review this function")

// Check pending steering
print(session.pendingSteeringCount)  // 0 after send
```

**Timing:** Steering added during processing applies to the *next* message, not the current one.

## Message Queue

Messages are processed in FIFO order:

```swift
// Concurrent sends are queued
Task { try await session.send("First") }   // 1st
Task { try await session.send("Second") }  // 2nd
Task { try await session.send("Third") }   // 3rd

// Check if processing
if session.isResponding {
    print("Session is busy")
}
```

### Cancellation

Tasks waiting in queue can be cancelled:

```swift
let task = Task {
    try await session.send("Long task")
}

// Cancel before processing starts
task.cancel()  // Removed from queue, doesn't consume slot
```

## Event Handling

Monitor session lifecycle with ``EventBus``:

```swift
let eventBus = EventBus()

eventBus.on(.promptSubmitted) { event in
    if let e = event as? SessionEvent {
        print("[Sent] \(e.value ?? "")")
    }
}

eventBus.on(.responseCompleted) { event in
    print("[Completed]")
}

let session = AgentSession(eventBus: eventBus, tools: tools) {
    Instructions("You are a helpful assistant.")
}
```

## Session Persistence

Save and restore conversations:

```swift
// Save
let snapshot = session.snapshot()
let data = try JSONEncoder().encode(snapshot)
try data.write(to: fileURL)

// Restore
let data = try Data(contentsOf: fileURL)
let snapshot = try JSONDecoder().decode(SessionSnapshot.self, from: data)
let restored = AgentSession.restore(from: snapshot, tools: tools)

// Continue conversation
let response = try await restored.send("Continue from where we left off")
```

## Session Replacement

Replace the underlying session for transcript compaction:

```swift
// Compact transcript (your logic)
let compactedTranscript = compactTranscript(session.transcript)

// Replace session
session.replaceSession(with: compactedTranscript)

// Next message uses new session
let response = try await session.send("Continue")
```

Safe to call during processing - current message continues with original session.

## Composable Agent Architecture

The power of SwiftAgent is that agents are Steps, and Steps can be nested and composed declaratively.

### Agent as a Step

```swift
struct ChatAgent: Step {
    @Session var session: LanguageModelSession

    func run(_ input: String) async throws -> String {
        try await session.respond(to: input).content
    }
}
```

### Nesting Agents

Agents can contain other agents:

```swift
struct ReviewAgent: Step {
    var body: some Step<String, String> {
        // First agent analyzes the code
        AnalyzeAgent()
        // Second agent suggests improvements
        SuggestAgent()
        // Third agent formats the output
        FormatAgent()
    }
}

struct AnalyzeAgent: Step {
    @Session var session: LanguageModelSession

    func run(_ code: String) async throws -> String {
        try await session.respond {
            Prompt("Analyze this code for issues:\n\(code)")
        }.content
    }
}
```

### REPL as a Step

Even a REPL can be a Step that composes other Steps:

```swift
struct AgentREPL: Step {
    let tools: [any Tool]

    func run(_ input: Void) async throws -> Void {
        let session = AgentSession(tools: tools) {
            Instructions("You are a coding assistant.")
        }

        print("Type 'exit' to quit.\n")

        while true {
            print("You> ", terminator: "")
            guard let input = readLine()?.trimmingCharacters(in: .whitespaces),
                  !input.isEmpty else { continue }

            if input.lowercased() == "exit" { break }

            do {
                let response = try await session.send(input)
                print("Agent> \(response.content)\n")
            } catch {
                print("Error: \(error)\n")
            }
        }
    }
}
```

### Declarative Agent Pipeline

Compose a complete agent workflow declaratively:

```swift
struct CodingAssistant: Step {
    let workingDirectory: String

    var body: some Step<String, String> {
        // Input validation
        Gate { input in
            guard !input.isEmpty else { return .block(reason: "Empty input") }
            return .pass(input)
        }

        // Main processing
        ProcessingAgent(workingDirectory: workingDirectory)

        // Output formatting
        Transform { output in
            "## Result\n\n\(output)"
        }
    }
}

struct ProcessingAgent: Step {
    let workingDirectory: String
    @Session var session: LanguageModelSession

    func run(_ input: String) async throws -> String {
        try await session.respond {
            Prompt("""
                Working directory: \(workingDirectory)
                User request: \(input)
                """)
        }.content
    }
}
```

### Hierarchical Agent Structure

Build complex agents by nesting:

```
MyApp
└── AgentREPL (Step)
    └── AgentSession
        └── CodingAssistant (Step)
            ├── Gate (validation)
            ├── ProcessingAgent (Step)
            │   └── LanguageModelSession
            └── Transform (formatting)
```

## Complete Example

```swift
import Foundation
import SwiftAgent
import AgentTools

@main
struct MyApp {
    static func main() async throws {
        let workingDir = FileManager.default.currentDirectoryPath
        let provider = AgentToolsProvider(workingDirectory: workingDir)

        try await AgentREPL(tools: provider.allTools())
            .run(())
    }
}
```

## Topics

### Creating Sessions

- ``AgentSession/init(id:eventBus:model:tools:instructions:)``
- ``AgentSession/init(id:eventBus:transcript:model:tools:)``

### Sending Messages

- ``AgentSession/send(_:)``
- ``AgentSession/steer(_:)``
- ``AgentSession/Response``

### Session State

- ``AgentSession/transcript``
- ``AgentSession/isResponding``
- ``AgentSession/pendingSteeringCount``

### Events

- ``EventBus``
- ``SessionEvent``

### Persistence

- ``AgentSession/snapshot()``
- ``AgentSession/restore(from:eventBus:model:tools:)``
- ``SessionSnapshot``
