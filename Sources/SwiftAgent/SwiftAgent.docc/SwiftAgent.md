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

### Core Protocols

- ``Step``
- ``StepBuilder``

### Primitive Steps

- ``Transform``
- ``Generate``
- ``GenerateText``
- ``Gate``
- ``Join``
- ``EmptyStep``

### Composite Steps

- ``Pipeline``
- ``Parallel``
- ``Race``
- ``Loop``
- ``Map``
- ``Reduce``

### Step Utilities

- ``Monitor``
- ``AnyStep``

### State Management

- ``Memory``
- ``Relay``

### Context System

- ``Context``
- ``ContextKey``
- ``Contextable``

### Session Management

- ``Session``
- ``AgentSession``
- ``LanguageModelSessionDelegate``

### Events

- ``EventBus``
- ``EventName``
- ``Event``

### Security

- ``PermissionConfiguration``
- ``PermissionMiddleware``
- ``SandboxExecutor``

### Error Handling

- ``GateError``
- ``ToolError``
- ``RaceError``
- ``ParallelError``
- ``LoopError``
