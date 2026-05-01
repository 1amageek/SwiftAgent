# Building an Agent Loop

Learn how to build a production-ready agent loop with Conversation.

## Overview

``Conversation`` is a thread-safe class for managing interactive multimodal conversations with language models. A `Conversation` wraps an externally-owned `LanguageModelSession` and a user-defined ``Step`` pipeline that maps a `Prompt` to a `String`. This guide shows how to build a complete agent application step by step.

## Basic Agent Loop

The simplest agent loop wraps a generation step and feeds it user input:

```swift
import SwiftAgent

let session = LanguageModelSession(
    model: .default,
    tools: []
) {
    Instructions("You are a helpful assistant.")
}

let conversation = Conversation(languageModelSession: session) {
    GenerateText<Prompt>(session: session) { prompt in prompt }
}

while true {
    print("You> ", terminator: "")
    guard let input = readLine(), !input.isEmpty else { continue }
    if input == "exit" { break }

    let response = try await conversation.send(input)
    print("Agent> \(response.content)")
}
```

### Why two pieces?

The `LanguageModelSession` owns the model, tool list, and instructions. The Step pipeline owns *how* prompts are processed (validation, retrieval augmentation, post-processing). Separating them lets you reuse a session across multiple Conversations or share a Step pipeline across sessions.

## Adding Tools

Tools are attached to the `LanguageModelSession`, not to the Conversation:

```swift
import AgentTools

let workingDir = FileManager.default.currentDirectoryPath
let tools: [any Tool] = [
    ReadTool(workingDirectory: workingDir),
    WriteTool(workingDirectory: workingDir),
    EditTool(workingDirectory: workingDir),
    GlobTool(workingDirectory: workingDir),
    GrepTool(workingDirectory: workingDir),
    ExecuteCommandTool(workingDirectory: workingDir),
    GitTool(),
    URLFetchTool(),
]

let session = LanguageModelSession(model: .default, tools: tools) {
    Instructions("""
        You are a coding assistant.
        Available tools: read, write, edit, glob, grep, bash, git
        """)
}

let conversation = Conversation(languageModelSession: session) {
    GenerateText<Prompt>(session: session) { $0 }
}
```

## Multimodal Prompts

`Conversation/send(_:)` accepts a `Prompt`, which can carry text, images, or other modalities supported by the model:

```swift
let prompt = Prompt {
    "Describe the contents of this image."
    Image(data: pngData)
}
let response = try await conversation.send(prompt)
```

A `String`-overload is provided for convenience and is wrapped in a `Prompt` automatically.

## Response Structure

``Conversation/Response`` carries the rendered text plus the transcript entries produced during the turn:

```swift
let response = try await conversation.send("Explain this code")

print(response.content)            // Generated text
for entry in response.entries {    // Prompt, tool calls, response
    print(entry)
}
print("Took: \(response.duration)")
```

## Steering

`steer()` adds context that will be merged into the **next** prompt instead of sending a separate message:

```swift
conversation.steer("Focus on performance")
conversation.steer("Use Swift concurrency")

let response = try await conversation.send("Review this function")
print(conversation.pendingSteeringCount)  // 0 after send
```

Steering enqueued during processing applies to the *next* turn, not the in-flight one.

## Message Queue and Cancellation

Concurrent `send` calls are processed in FIFO order. A cancelled `Task` is removed from the queue before it consumes a slot:

```swift
Task { try await conversation.send("First") }   // 1st
Task { try await conversation.send("Second") }  // 2nd

let cancellable = Task {
    try await conversation.send("Maybe later")
}
cancellable.cancel()
```

Use ``Conversation/isResponding`` to check whether a turn is in flight.

## Persistence

Conversations are persisted via ``SessionSnapshot`` and the ``SessionStore`` protocol. ``FileSessionStore`` and ``InMemorySessionStore`` are provided.

```swift
let store = FileSessionStore(directory: .documentsDirectory)

// Save the current state
let snapshot = conversation.snapshot()
try await store.save(snapshot)

// Resume in a future run by replaying the transcript into a new session
if let saved = try await store.load(id: snapshot.id) {
    let resumed = LanguageModelSession(
        model: .default,
        tools: tools,
        transcript: saved.transcript
    ) { Instructions("…") }

    let conversation = Conversation(
        id: saved.id,
        languageModelSession: resumed
    ) {
        GenerateText<Prompt>(session: resumed) { $0 }
    }
}
```

## Event Handling

Inject an ``EventBus`` via ``Step/context(_:)`` and decorate steps with `.emit(_:on:)`:

```swift
extension EventName {
    static let processingStarted = EventName("processingStarted")
    static let processingCompleted = EventName("processingCompleted")
}

let eventBus = EventBus()
eventBus.on(.processingStarted) { _ in print("[Started]") }
eventBus.on(.processingCompleted) { _ in print("[Completed]") }

let pipeline = GenerateText<Prompt>(session: session) { $0 }
    .emit(.processingStarted, on: .before)
    .emit(.processingCompleted, on: .after)
    .context(eventBus)
```

## Composable Agent Architecture

A Conversation is built from Steps, and Steps are themselves Conversation-friendly. This is what lets you scale from a one-line wrapper to a multi-stage agent.

### Agent as a Step

```swift
struct ChatAgent: Step {
    @Session var session: LanguageModelSession

    func run(_ input: Prompt) async throws -> String {
        try await session.respond { input }.content
    }
}
```

### Declarative Pipeline

```swift
struct CodingAssistant: Step {
    @Session var session: LanguageModelSession

    var body: some Step<Prompt, String> {
        Gate { prompt in
            guard !prompt.isEmpty else { return .block(reason: "Empty prompt") }
            return .pass(prompt)
        }
        GenerateText<Prompt>(session: session) { $0 }
        Transform { "## Result\n\n\($0)" }
    }
}

let conversation = Conversation(languageModelSession: session) {
    CodingAssistant()
}
```

### Hierarchical Structure

```
MyApp
└── REPL loop
    └── Conversation
        └── CodingAssistant (Step with Prompt → String body)
            ├── Gate (validation)
            ├── GenerateText (LLM call)
            └── Transform (post-processing)
```

## Topics

### Creating Sessions

- ``Conversation/init(id:languageModelSession:step:)``

### Sending Messages

- ``Conversation/send(_:)-(Prompt)``
- ``Conversation/send(_:)-(String)``
- ``Conversation/steer(_:)-(Prompt)``
- ``Conversation/steer(_:)-(String)``
- ``Conversation/Response``

### Session State

- ``Conversation/transcript``
- ``Conversation/isResponding``
- ``Conversation/pendingSteeringCount``

### Events

- ``EventBus``
- ``EventName``
- ``EventTiming``

### Persistence

- ``Conversation/snapshot()``
- ``SessionSnapshot``
- ``SessionStore``
- ``FileSessionStore``
- ``InMemorySessionStore``
