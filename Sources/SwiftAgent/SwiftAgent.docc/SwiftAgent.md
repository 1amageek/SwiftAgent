# ``SwiftAgent``

A type-safe, declarative framework for building AI agents with composable async pipelines.

@Metadata {
    @DisplayName("SwiftAgent")
}

## Overview

SwiftAgent provides a functional composition pattern for building AI agent workflows. It uses a pipeline-based architecture where data flows through a series of transformations, similar to function composition in functional programming or middleware patterns in web frameworks.

The core abstraction is the ``Step`` protocol, which represents an async transformation from `Input` to `Output`. Steps can be composed together to form complex processing pipelines.

```swift
// A simple pipeline that transforms input through multiple steps
struct MyPipeline: Step {
    var body: some Step<String, String> {
        Transform { $0.trimmingCharacters(in: .whitespaces) }
        GenerateText { Prompt($0) }
        Transform { $0.uppercased() }
    }
}
```

### Key Design Principles

- **Type-safe composition**: Input and output types are checked at compile time
- **Async-first**: All operations are async/await based
- **Functional pipelines**: Data flows through composable transformations
- **Context propagation**: Values flow through TaskLocal-based context system

## Topics

### Essentials

- <doc:GettingStarted>
- <doc:CoreConcepts>

### Steps

- ``Step``
- ``StepBuilder``

### Steps - Primitives

Basic building blocks for data transformation and generation.

- ``Transform``
- ``Generate``
- ``GenerateText``
- ``Gate``
- ``Join``
- ``EmptyStep``

### Steps - Composition

Combine multiple steps into complex workflows.

- ``Pipeline``
- ``Parallel``
- ``Race``
- ``Loop``
- ``Map``
- ``Reduce``

### Steps - Error Handling

Handle errors, retries, and timeouts.

- ``Try``
- ``RetryStep``
- ``TimedStep``
- ``MapErrorStep``

### Steps - Utilities

Type erasure and debugging.

- ``Monitor``
- ``AnyStep``

### State Management

- <doc:StateManagementGuide>
- ``Memory``
- ``Relay``

### Context System

- <doc:ContextGuide>
- ``Context``
- ``ContextKey``
- ``Contextable``

### Session Management

- <doc:AgentSessionGuide>
- ``Session``
- ``AgentSession``
- ``LanguageModelSessionDelegate``

### Events

- ``EventBus``
- ``EventName``
- ``Event``

### Security

- <doc:SecurityGuide>
- ``SecurityConfiguration``
- ``PermissionConfiguration``
- ``PermissionRule``
- ``SandboxExecutor``

### Errors

- ``GateError``
- ``ToolError``
- ``RaceError``
- ``ParallelError``
- ``LoopError``
- ``StepTimeoutError``
