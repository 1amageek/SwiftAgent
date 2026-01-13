# Core Concepts

Understand the fundamental building blocks of SwiftAgent.

## Overview

SwiftAgent is built on a pipeline-based architecture inspired by functional programming patterns like function composition and Railway Oriented Programming. This article explains the core concepts that make up the framework.

### Pipeline Architecture

SwiftAgent uses a data pipeline model where:

1. Data enters at the beginning of a pipeline
2. Each step transforms the data
3. The output of one step becomes the input of the next
4. The final step's output is the pipeline's result

```
Input → Step1 → Step2 → Step3 → Output
```

This is similar to:
- Unix pipes (`cat file | grep pattern | sort`)
- Middleware patterns in web frameworks (Express.js, Koa)
- Combine/RxSwift operator chains
- Kleisli composition in functional programming

### Step: The Fundamental Unit

``Step`` is the core protocol representing an async transformation:

```swift
public protocol Step<Input, Output> {
    associatedtype Input: Sendable
    associatedtype Output: Sendable
    associatedtype Body = Never

    @StepBuilder var body: Body { get }

    @discardableResult
    func run(_ input: Input) async throws -> Output
}
```

Key properties:
- **Type-safe**: Input and Output types are enforced at compile time
- **Async**: All transformations are async/await based
- **Composable**: Steps chain together when Output of one matches Input of the next
- **Two implementation styles**: Implement `run(_:)` directly for primitive steps, or define `body` for declarative composition

### Primitive vs Declarative Steps

**Primitive Steps** implement `run(_:)` directly:

```swift
struct FetchData: Step {
    func run(_ input: URL) async throws -> Data {
        let (data, _) = try await URLSession.shared.data(from: input)
        return data
    }
}
```

**Declarative Steps** define a `body` property to compose other steps:

```swift
struct MyPipeline: Step {
    var body: some Step<String, Int> {
        Transform { $0.count }        // String → Int
    }
}
```

When `body` is defined, `run(_:)` is automatically implemented to delegate to the body.

### Memory and Relay: State Management

``Memory`` stores mutable state with reference semantics:

```swift
@Memory var counter: Int = 0
counter += 1  // Modifies the stored value

// Get a Relay for sharing with other steps
let relay = $counter
```

``Relay`` provides indirect access through getter/setter closures:

```swift
struct ChildStep: Step {
    let counter: Relay<Int>

    func run(_ input: String) async throws -> String {
        counter.wrappedValue += 1
        return input
    }
}
```

Memory uses a Mutex internally for thread safety.

### Context: TaskLocal Propagation

The ``Context`` system propagates values through the call stack using TaskLocal:

```swift
// Define a contextable type
@Contextable
struct AppConfig {
    static var defaultValue: AppConfig { AppConfig(maxRetries: 3) }
    let maxRetries: Int
}

// Access in a Step
struct MyStep: Step {
    @Context var config: AppConfig

    func run(_ input: String) async throws -> String {
        // Use config.maxRetries
    }
}

// Provide the context
try await MyStep()
    .context(AppConfig(maxRetries: 5))
    .run(input)
```

This enables dependency injection without explicit parameter passing.

### Session: Language Model Integration

``AgentSession`` manages interactive conversations with thread-safe message queuing:

```swift
let session = AgentSession(tools: myTools) {
    Instructions("You are a helpful assistant.")
}

let response = try await session.send("Hello!")
print(response.content)
```

Features:
- FIFO message queue with cancellation support
- Steering messages for context injection
- Session replacement for transcript compaction

### Gate: Flow Control

``Gate`` can transform input or block execution:

```swift
Gate { input in
    if isValid(input) {
        return .pass(transform(input))
    } else {
        return .block(reason: "Invalid input")
    }
}
```

When a gate blocks, it throws ``GateError/blocked(reason:)``.

### Parallel vs Race: Concurrency Patterns

**Parallel** (best-effort): Collects all successful results

```swift
Parallel<Query, SearchResult> {
    SearchGoogle()     // May fail
    SearchBing()       // May fail
    SearchDuckDuckGo() // May fail
}
// Returns results from all that succeed
```

**Race** (first-success): Returns the first successful result

```swift
Race<URL, Data> {
    FetchFromPrimary()   // Fast but unreliable
    FetchFromSecondary() // Slow but stable
}
// Returns whichever succeeds first
```

### EventBus: Event System

``EventBus`` provides type-safe event emission and handling:

```swift
// Define event names
extension EventName {
    static let taskCompleted = EventName("taskCompleted")
}

// Emit events
MyStep()
    .emit(.taskCompleted, on: .after)

// Handle events
let eventBus = EventBus()
eventBus.on(.taskCompleted) { event in
    print("Task completed!")
}
```

### Security: Permissions and Sandboxing

The security layer provides:

- **PermissionMiddleware**: Allow/deny rules for tool execution
- **SandboxExecutor**: macOS sandbox for command execution
- **Guardrail**: Declarative step-level security policies

```swift
MyStep()
    .guardrail {
        Allow(.tool("Read"))
        Deny(.bash("rm:*"))
        Sandbox(.restrictive)
    }
```

## Summary

| Concept | Purpose |
|---------|---------|
| Step | Async transformation unit (primitive or declarative) |
| Memory/Relay | Mutable state sharing |
| Context | TaskLocal value propagation |
| AgentSession | Interactive LLM conversations |
| Gate | Flow control (pass/block) |
| Parallel | Collect all successes |
| Race | Return first success |
| EventBus | Event emission/handling |
| Security | Permissions and sandboxing |
