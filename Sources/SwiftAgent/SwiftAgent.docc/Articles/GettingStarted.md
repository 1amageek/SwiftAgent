# Getting Started

Build your first AI agent pipeline with SwiftAgent.

## Overview

SwiftAgent uses a pipeline-based architecture for AI agent workflows. You compose small, reusable ``Step`` instances into larger pipelines that transform data from input to output.

### Understanding the Step Protocol

The ``Step`` protocol is the fundamental building block:

```swift
public protocol Step<Input, Output> {
    associatedtype Input: Sendable
    associatedtype Output: Sendable
    associatedtype Body = Never

    @StepBuilder var body: Body { get }
    func run(_ input: Input) async throws -> Output
}
```

Every step takes an input, performs an async transformation, and produces an output. Steps can be implemented in two ways:

- **Primitive steps**: Implement `run(_:)` directly (use `Body = Never`)
- **Declarative steps**: Define a `body` property to compose other steps

### Creating Your First Step

The simplest way to create a step is with ``Transform``:

```swift
let uppercase = Transform<String, String> { input in
    input.uppercased()
}

let result = try await uppercase.run("hello") // "HELLO"
```

### Composing Steps Declaratively

Define a `body` property to compose multiple steps into a pipeline:

```swift
struct TextProcessor: Step {
    var body: some Step<String, String> {
        Transform { $0.trimmingCharacters(in: .whitespaces) }
        Transform { $0.lowercased() }
        Transform { $0.replacingOccurrences(of: " ", with: "-") }
    }
}

let processor = TextProcessor()
let result = try await processor.run("  Hello World  ") // "hello-world"
```

When you define a `body`, the `run(_:)` method is automatically implemented. Steps in the body are executed sequentially, with each step's output becoming the next step's input.

### Adding LLM Generation

Use ``GenerateText`` to integrate language model generation:

```swift
struct Summarizer: Step {
    @Session var session: LanguageModelSession

    var body: some Step<String, String> {
        Transform { "Summarize this text:\n\n\($0)" }
        GenerateText(session: session) { Prompt($0) }
    }
}
```

### Sharing State Between Steps

Use ``Memory`` to share mutable state across steps:

```swift
struct Counter: Step {
    @Memory var count: Int = 0

    var body: some Step<String, String> {
        Transform { [self] input in
            count += 1
            return "\(input) (processed \(count) times)"
        }
    }
}
```

Pass state to child steps using ``Relay``:

```swift
struct Parent: Step {
    @Memory var visited: Set<URL> = []

    func run(_ input: URL) async throws -> Data {
        try await ChildStep(visited: $visited).run(input)
    }
}

struct ChildStep: Step {
    let visited: Relay<Set<URL>>

    func run(_ input: URL) async throws -> Data {
        guard !visited.contains(input) else {
            throw AlreadyVisitedError()
        }
        visited.insert(input)
        // fetch data...
    }
}
```

### Flow Control with Gate

Use ``Gate`` to conditionally block or transform data:

```swift
struct ValidatedPipeline: Step {
    var body: some Step<String, String> {
        Gate { input in
            guard !input.isEmpty else {
                return .block(reason: "Input cannot be empty")
            }
            return .pass(input.trimmingCharacters(in: .whitespaces))
        }
        ProcessingStep()
    }
}
```

### Parallel Execution

Run steps concurrently with ``Parallel`` or ``Race``:

```swift
// Collect all successful results
let parallel = Parallel<URL, Data> {
    FetchFromServer1()
    FetchFromServer2()
    FetchFromServer3()
}
let results = try await parallel.run(url) // [Data, Data, ...]

// Return first success (fallback pattern)
let race = Race<URL, Data> {
    FetchFromPrimary()
    FetchFromBackup()
}
let data = try await race.run(url)
```

## Next Steps

- Learn about <doc:CoreConcepts> for deeper understanding
- Explore ``Context`` for dependency injection
- See ``AgentSession`` for interactive conversations
